import Foundation
import SwiftData
import AuthenticationServices

extension Notification.Name {
    /// Posted by VisitStore and WantToGoStore after any local change,
    /// so SyncManager can back it up without the stores knowing about
    /// sync. Local saves never wait for the network.
    static let coffeeShopDataChanged = Notification.Name("com.lexissapphirestudio.coffeeshopapp.dataChanged")
    /// Posted by SyncManager when a remote settings sync changes the
    /// prompts setting, so CheckInManager can start or stop monitoring.
    static let coffeeShopSettingsChanged = Notification.Name("com.lexissapphirestudio.coffeeshopapp.settingsChanged")
}

enum SyncManagerError: Error, LocalizedError {
    case notSignedIn
    case notConfigured
    case noSession
    case syncFailed(message: String)
    case deleteFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to back up your log."
        case .notConfigured:
            return "Backup is not set up yet."
        case .noSession:
            return "Your session expired. Please sign in again."
        case .syncFailed(let message), .deleteFailed(let message):
            return message
        }
    }
}

/// Owns backup and account sync (Sprint 6, Story S14). Local first: a
/// check in saves on the phone and the sync follows when it can. A
/// failed sync never loses local data and never blocks the app.
/// Sync runs on sign in, on launch, when the app returns to the front,
/// and a short time after any local change. The Supabase project does
/// not exist yet (Sprint 0 account step), so until it does the manager
/// reports not configured and the app runs local only.
@MainActor
final class SyncManager: ObservableObject {
    enum Status: Equatable {
        case signedOut
        case notConfigured
        case idle(lastSync: Date?, summary: String?)
        case syncing
        case failed(message: String)
    }

    @Published private(set) var status: Status = .signedOut
    @Published private(set) var isSignedIn = false
    /// The name Apple shared on the first sign in, if any.
    var displayName: String? { auth.displayName }
    /// The email Apple shared on the first sign in, if any. This may be
    /// a private relay address; the app never emails it.
    var email: String? { auth.email }
    /// Visits and Want To Go entries waiting for backup.
    @Published private(set) var pendingCount = 0
    /// Visits waiting for backup. The signed out banner shows only
    /// when this is above zero (Flow H step 4).
    @Published private(set) var unsyncedVisitCount = 0
    /// The counted confirmation from the last sync, for the sign in
    /// screen and Settings.
    @Published private(set) var lastConfirmation: String?

    private let context: ModelContext
    private let auth: AuthManager
    private let client: SupabaseSyncClient
    private var isSyncing = false
    private var lastSyncAttempt: Date?
    private var debounceTask: Task<Void, Never>?
    private var dataChangedObserver: NSObjectProtocol?

    init(context: ModelContext, auth: AuthManager, client: SupabaseSyncClient = SupabaseSyncClient()) {
        self.context = context
        self.auth = auth
        self.client = client
        dataChangedObserver = NotificationCenter.default.addObserver(
            forName: .coffeeShopDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        }
    }

    deinit {
        if let dataChangedObserver {
            NotificationCenter.default.removeObserver(dataChangedObserver)
        }
        debounceTask?.cancel()
    }

    // MARK: - Session

    /// Restores a saved session on launch and kicks off a sync when one
    /// is waiting.
    func restoreSession() async {
        await auth.restoreSession()
        isSignedIn = auth.isSignedIn
        refreshCounts()
        guard isSignedIn else {
            status = .signedOut
            return
        }
        if !client.isConfigured {
            status = .notConfigured
            return
        }
        let settings = UserSettings.current(in: context)
        status = .idle(lastSync: settings.lastSyncAt, summary: settings.lastSyncSummary)
        await syncIfNeeded()
    }

    /// Signs in with an Apple credential, then runs the first sync and
    /// returns the counted confirmation line (Flow H step 3). When the
    /// backup service is not set up yet, the sign in still succeeds and
    /// the message says so honestly.
    func signIn(with credential: ASAuthorizationAppleIDCredential) async throws -> String {
        let result: AuthManager.SignInResult
        do {
            result = try await auth.completeSignIn(with: credential)
        } catch {
            throw SyncManagerError.syncFailed(message: plainMessage(for: error))
        }
        isSignedIn = true
        refreshCounts()
        switch result {
        case .backedUp:
            return try await syncNow()
        case .localOnly:
            status = .notConfigured
            return "Signed in. Backup is not set up yet, so your log still lives only on this phone for now."
        }
    }

    /// Signs out. The local log stays on this phone, untouched (Flow H
    /// step 5); every record goes back to local, so the next sign in
    /// backs the whole log up again through the merge rule.
    func signOut() async {
        await auth.signOut()
        isSignedIn = false
        VisitStore(context: context).markAllLocal()
        lastConfirmation = nil
        status = .signedOut
        refreshCounts()
    }

    // MARK: - Sync

    /// Syncs now when signed in and the backend is configured, and when
    /// something is waiting or the last attempt is stale. Silent when
    /// there is nothing to do; failures land in `status`.
    func syncIfNeeded() async {
        guard isSignedIn, client.isConfigured, !isSyncing else { return }
        refreshCounts()
        let stale = lastSyncAttempt.map { Date().timeIntervalSince($0) > 300 } ?? true
        guard pendingCount > 0 || stale else { return }
        lastSyncAttempt = Date()
        do {
            _ = try await syncNow()
        } catch {
            // Status already carries the failure; a background sync
            // never throws at its caller.
        }
    }

    /// Runs a full sync and returns the counted confirmation line.
    /// Throws a plain language error on failure; local data is never
    /// at risk, and the failure is recorded in `status`.
    @discardableResult
    func syncNow() async throws -> String {
        guard !isSyncing else { return lastConfirmation ?? "" }
        guard isSignedIn else { throw SyncManagerError.notSignedIn }
        guard client.isConfigured else { throw SyncManagerError.notConfigured }
        guard let token = await auth.validAccessToken() else { throw SyncManagerError.noSession }
        guard let ownerIDText = auth.supabaseUserID,
              let ownerID = UUID(uuidString: ownerIDText) else {
            throw SyncManagerError.noSession
        }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }
        do {
            // 1. Tombstones first, so a deleted visit can never come
            // back from the backup.
            let tombstones = SyncedDeletion.all(in: context)
            try await client.deleteVisits(
                ids: tombstones.filter { $0.kind == .visit }.map(\.recordID),
                accessToken: token
            )
            try await client.deleteWantToGo(
                ids: tombstones.filter { $0.kind == .wantToGo }.map(\.recordID),
                accessToken: token
            )
            SyncedDeletion.removeAll(tombstones, in: context)

            // 2. Fetch the remote state.
            let remoteVisits = try await client.fetchVisits(accessToken: token)
            let remoteWantToGo = try await client.fetchWantToGo(accessToken: token)
            let remoteCompanions = try await client.fetchCompanions(accessToken: token)
            let remoteSettings = try await client.fetchSettings(userID: ownerID, accessToken: token)

            // 3. Plans: pure merge decisions, no side effects.
            let localVisits = fetchAllVisits()
            let localWantToGo = fetchAllWantToGo()
            let localCompanions = fetchAllCompanions()
            let settings = UserSettings.current(in: context)
            let companionPlan = SyncPlan.companions(local: localCompanions, remote: remoteCompanions)
            let visitPlan = SyncPlan.visits(local: localVisits, remote: remoteVisits)
            let wantToGoPlan = SyncPlan.wantToGo(local: localWantToGo, remote: remoteWantToGo)
            let settingsPlan = SyncPlan.settings(local: settings, remote: remoteSettings)

            // 4. Apply the remote changes locally, then save, so the
            // merged log is safe even if the upload below fails.
            applyCompanionPlan(companionPlan)
            applyVisitPlan(visitPlan, remap: companionPlan.remapIDs)
            applyWantToGoPlan(wantToGoPlan)
            let promptsChanged = applySettingsPlan(settingsPlan, settings: settings)
            try context.save()
            if promptsChanged {
                NotificationCenter.default.post(name: .coffeeShopSettingsChanged, object: nil)
            }

            // 5. Upload the local changes.
            let remoteVisitsByID = Dictionary(uniqueKeysWithValues: remoteVisits.map { ($0.id, $0) })
            var uploadedPhotoPaths: [UUID: String] = [:]
            for visit in visitPlan.toUpload {
                guard let filename = visit.photoFilename,
                      let data = VisitPhotoStore.data(filename: filename) else { continue }
                let path = SupabaseSyncClient.photoPath(ownerID: ownerID, visitID: visit.id)
                do {
                    try await client.uploadPhoto(data, path: path, accessToken: token)
                    uploadedPhotoPaths[visit.id] = path
                } catch {
                    // One failed photo never fails the sync; the visit
                    // still backs up, and the photo retries next time.
                    print("Photo upload failed for visit \(visit.id): \(error.localizedDescription)")
                }
            }
            let visitDTOs = visitPlan.toUpload.map { visit in
                let path = uploadedPhotoPaths[visit.id] ?? remoteVisitsByID[visit.id]?.photoPath
                return VisitDTO(from: visit, ownerID: ownerID, photoPath: path)
            }
            try await client.upsertVisits(visitDTOs, accessToken: token)
            try await client.deleteVisits(ids: visitPlan.toDeleteRemoteIDs, accessToken: token)
            try await client.upsertWantToGo(
                wantToGoPlan.toUpload.map { WantToGoDTO(from: $0, ownerID: ownerID) },
                accessToken: token
            )
            try await client.deleteWantToGo(ids: wantToGoPlan.toDeleteRemoteIDs, accessToken: token)
            try await client.upsertCompanions(
                companionPlan.toUpload.map { CompanionDTO(from: $0, ownerID: ownerID) },
                accessToken: token
            )
            if settingsPlan == .uploadLocal || settingsPlan == .uploadLocalNewer {
                try await client.upsertSettings(UserSettingsDTO(from: settings, userID: ownerID), accessToken: token)
            }

            // 6. Download photos for visits that arrived with one. A
            // failed download leaves the visit backed up without its
            // photo; it retries on the next sync.
            for dto in visitPlan.toInsert where dto.photoPath != nil {
                await downloadPhoto(for: dto, token: token)
            }
            for (_, remote) in visitPlan.toUpdateLocal where remote.photoPath != nil {
                await downloadPhoto(for: remote, token: token)
            }

            // 7. Mark the uploads synced and record the confirmation.
            for visit in visitPlan.toUpload { visit.syncState = .synced }
            for entry in wantToGoPlan.toUpload { entry.syncState = .synced }
            let confirmation = VisitMerge.confirmationLine(
                backedUp: visitPlan.toUpload.count,
                duplicatesMerged: visitPlan.duplicatesMerged
            )
            settings.lastSyncAt = Date()
            settings.lastSyncSummary = confirmation
            settings.updatedAt = Date()
            try context.save()
            lastConfirmation = confirmation
            status = .idle(lastSync: settings.lastSyncAt, summary: confirmation)
            refreshCounts()
            return confirmation
        } catch {
            let message = plainMessage(for: error)
            status = .failed(message: message)
            refreshCounts()
            throw SyncManagerError.syncFailed(message: message)
        }
    }

    // MARK: - Account deletion

    /// Deletes the account and its data, inside the app (Flow I step 4).
    /// Remote rows and photos go first, then the auth user through the
    /// edge function, and only when both succeed does the local log
    /// leave the phone. A failure at any step throws and keeps the
    /// local log untouched, so a half finished deletion cannot strand
    /// the user with no copy at all. When no backend is configured,
    /// there is no remote data, so only the local wipe runs.
    func deleteAccount() async throws {
        guard isSignedIn else { throw SyncManagerError.notSignedIn }
        if client.isConfigured {
            guard let token = await auth.validAccessToken() else { throw SyncManagerError.noSession }
            guard let ownerIDText = auth.supabaseUserID,
                  let ownerID = UUID(uuidString: ownerIDText) else {
                throw SyncManagerError.noSession
            }
            do {
                let remoteVisits = try await client.fetchVisits(accessToken: token)
                try await client.deleteVisits(ids: remoteVisits.map(\.id), accessToken: token)
                try await client.deletePhotos(
                    paths: remoteVisits.compactMap(\.photoPath),
                    accessToken: token
                )
                let remoteWantToGo = try await client.fetchWantToGo(accessToken: token)
                try await client.deleteWantToGo(ids: remoteWantToGo.map(\.id), accessToken: token)
                let remoteCompanions = try await client.fetchCompanions(accessToken: token)
                try await client.deleteCompanions(ids: remoteCompanions.map(\.id), accessToken: token)
                try await client.deleteSettings(userID: ownerID, accessToken: token)
                try await client.deleteAccount(accessToken: token)
            } catch {
                throw SyncManagerError.deleteFailed(message: plainMessage(for: error))
            }
        }
        deleteAllLocalData()
        auth.clearLocalSession()
        isSignedIn = false
        lastConfirmation = nil
        status = .signedOut
        refreshCounts()
    }

    // MARK: - Counts

    func refreshCounts() {
        let visits = fetchAllVisits()
        let entries = fetchAllWantToGo()
        unsyncedVisitCount = visits.filter { $0.syncState != .synced }.count
        pendingCount = unsyncedVisitCount + entries.filter { $0.syncState != .synced }.count
    }

    // MARK: - Private helpers

    private func scheduleSync() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncIfNeeded()
        }
    }

    private func fetchAllVisits() -> [Visit] {
        (try? context.fetch(FetchDescriptor<Visit>())) ?? []
    }

    private func fetchAllWantToGo() -> [WantToGoEntry] {
        (try? context.fetch(FetchDescriptor<WantToGoEntry>())) ?? []
    }

    private func fetchAllCompanions() -> [Companion] {
        (try? context.fetch(FetchDescriptor<Companion>())) ?? []
    }

    private func deleteAllLocalData() {
        for visit in fetchAllVisits() { context.delete(visit) }
        for entry in fetchAllWantToGo() { context.delete(entry) }
        for companion in fetchAllCompanions() { context.delete(companion) }
        for arrival in (try? context.fetch(FetchDescriptor<DismissedArrival>())) ?? [] {
            context.delete(arrival)
        }
        SyncedDeletion.removeAll(SyncedDeletion.all(in: context), in: context)
        let settings = UserSettings.current(in: context)
        settings.autoCheckInPromptsEnabled = true
        settings.shareNotesByDefault = false
        settings.sharerName = nil
        settings.lastPromptDate = nil
        settings.lastPromptShopName = nil
        settings.lastSyncAt = nil
        settings.lastSyncSummary = nil
        settings.backupReminderDismissed = false
        settings.updatedAt = Date()
        try? context.save()
        // Every photo file is now orphaned; the cleanup removes them all.
        VisitStore(context: context).cleanupOrphanedPhotos()
    }

    private func applyCompanionPlan(_ plan: SyncPlan.CompanionPlan) {
        for dto in plan.toInsert {
            context.insert(dto.makeCompanion())
        }
    }

    private func applyVisitPlan(_ plan: SyncPlan.VisitPlan, remap: [UUID: UUID]) {
        for loser in plan.toDeleteLocal {
            context.delete(loser)
        }
        for (local, remote) in plan.toUpdateLocal {
            apply(dto: remote, to: local, remap: remap)
            local.syncState = .synced
        }
        for dto in plan.toInsert {
            var adjusted = dto
            adjusted.companionIds = dto.companionIds.map { remap[$0] ?? $0 }
            context.insert(adjusted.makeVisit())
        }
    }

    private func apply(dto: VisitDTO, to visit: Visit, remap: [UUID: UUID]) {
        visit.shopID = dto.shopId
        visit.shopName = dto.shopName
        visit.neighborhood = dto.neighborhood
        visit.address = dto.address
        visit.checkedInAt = dto.checkedInAt
        visit.sourceRaw = dto.source
        visit.rating = dto.rating
        visit.tags = dto.tags
        visit.orderText = dto.orderText
        visit.note = dto.note
        visit.companionIDs = dto.companionIds.map { remap[$0] ?? $0 }
        // A remote photo replaces the local one; a remote visit with no
        // photo never wipes a photo this phone already has.
        if dto.photoPath != nil {
            visit.photoFilename = VisitPhotoStore.filename(for: visit.id)
        }
        visit.isUnverifiedShop = dto.isUnverifiedShop
        visit.createdAt = dto.createdAt
        visit.updatedAt = dto.updatedAt
    }

    private func applyWantToGoPlan(_ plan: SyncPlan.WantToGoPlan) {
        for loser in plan.toDeleteLocal {
            context.delete(loser)
        }
        for (local, remote) in plan.toUpdateLocal {
            local.shopID = remote.shopId
            local.shopName = remote.shopName
            local.neighborhood = remote.neighborhood
            local.address = remote.address
            local.sharedBy = remote.sharedBy
            local.noteFromSharer = remote.noteFromSharer
            local.addedAt = remote.addedAt
            local.updatedAt = remote.updatedAt
            local.syncState = .synced
        }
        for dto in plan.toInsert {
            context.insert(dto.makeEntry())
        }
    }

    /// Applies a remote settings row. Returns true when the prompts
    /// setting changed, so monitoring can restart or stop.
    @discardableResult
    private func applySettingsPlan(_ plan: SyncPlan.SettingsPlan, settings: UserSettings) -> Bool {
        guard case .applyRemote(let dto) = plan else { return false }
        let promptsChanged = settings.autoCheckInPromptsEnabled != dto.autoCheckInPromptsEnabled
        settings.autoCheckInPromptsEnabled = dto.autoCheckInPromptsEnabled
        settings.shareNotesByDefault = dto.shareNotesByDefault
        settings.sharerName = dto.sharerName
        settings.updatedAt = dto.updatedAt
        return promptsChanged
    }

    private func downloadPhoto(for dto: VisitDTO, token: String) async {
        guard let path = dto.photoPath else { return }
        let filename = VisitPhotoStore.filename(for: dto.id)
        guard VisitPhotoStore.load(filename: filename) == nil else { return }
        guard let data = try? await client.downloadPhoto(path: path, accessToken: token) else { return }
        try? VisitPhotoStore.saveData(data, for: dto.id)
    }

    private func plainMessage(for error: Error) -> String {
        if let syncError = error as? SupabaseSyncError {
            switch syncError {
            case .notConfigured:
                return "Backup is not set up yet."
            case .unauthorized:
                return "Your session expired. Please sign in again."
            case .requestFailed:
                return "Could not reach the backup service. Check your connection and try again."
            case .badResponse:
                return "The backup service did not respond as expected. Try again."
            case .decodingFailed:
                return "The backup sent data the app could not read. Try again."
            case .missingIdentityToken:
                return "Sign in did not return an account. Please try again."
            }
        }
        if let managerError = error as? SyncManagerError {
            return managerError.localizedDescription
        }
        return "Something went wrong with the backup. Try again."
    }
}
