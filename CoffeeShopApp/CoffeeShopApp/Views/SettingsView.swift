import SwiftUI
import SwiftData

/// Settings (Screen 16): the account and backup sections (Sprint 6,
/// Stories S13, S14) sit first, above the prompts, location, sharing,
/// directory, and about sections. Signing out never deletes the local
/// log; deleting the account does, and says so before it runs.
struct SettingsView: View {
    @Query private var settingsRows: [UserSettings]
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var notificationService: NotificationService
    @EnvironmentObject private var directoryStore: DirectoryStore
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.modelContext) private var modelContext

    @State private var showSignIn = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var deleteInProgress = false
    @State private var deleteError: String?

    private var settings: UserSettings? { settingsRows.first }

    var body: some View {
        NavigationStack {
            Form {
                if showBackupBanner {
                    backupBannerSection
                }
                accountSection
                backupSection
                promptsSection
                notificationsSection
                locationSection
                sharingSection
                directorySection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                await notificationService.refreshStatus()
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await syncManager.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your log stays on this phone. It will stop backing up until you sign in again.")
            }
            .confirmationDialog(
                "Delete my account and data?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your account, your backed up visits, your Want To Go list, your visit photos, and the log on this phone. This cannot be undone.")
            }
            .alert("Delete did not work", isPresented: deleteErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "Nothing was deleted. Please try again.")
            }
        }
    }

    /// The banner shows only when signed out with visits waiting for
    /// backup (Flow H step 4).
    private var showBackupBanner: Bool {
        !syncManager.isSignedIn && syncManager.unsyncedVisitCount > 0
    }

    private var backupBannerSection: some View {
        Section {
            BackupBannerView { showSignIn = true }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if syncManager.isSignedIn {
                signedInRows
            } else {
                signedOutRows
            }
        }
    }

    private var signedOutRows: some View {
        Group {
            Text("Back up your Visited and Want To Go lists so a new phone keeps them.")
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            Button("Sign In for Backup") { showSignIn = true }
        }
    }

    private var signedInRows: some View {
        Group {
            Text("Signed in with Apple")
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            if let displayName = syncManager.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            if let email = syncManager.email, !email.isEmpty {
                Text(email)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            Button("Sign Out") { showSignOutConfirm = true }
            Button("Delete My Account and Data", role: .destructive) {
                showDeleteConfirm = true
            }
            if deleteInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Deleting your account")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                }
            }
        }
    }

    // MARK: - Backup

    private var backupSection: some View {
        Section("Backup") {
            Text(backupStatusText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            if let backupDetailText {
                Text(backupDetailText)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            if syncManager.isSignedIn {
                Button("Sync Now") {
                    Task {
                        do {
                            _ = try await syncManager.syncNow()
                        } catch {
                            // The status line carries the failure.
                        }
                    }
                }
                .disabled(syncManager.status == .syncing)
            }
        }
    }

    private var backupStatusText: String {
        switch syncManager.status {
        case .signedOut:
            return "Local Only. Your log lives on this phone."
        case .notConfigured:
            return "Backup Not Set Up. Your log lives on this phone."
        case .idle(let lastSync, _):
            if let lastSync {
                return "Backed Up. Last backup \(mediumDate(lastSync))."
            }
            return "Backed Up."
        case .syncing:
            return "Syncing"
        case .failed:
            return "Backup did not finish. Your log is safe on this phone."
        }
    }

    private var backupDetailText: String? {
        switch syncManager.status {
        case .signedOut:
            return "Sign in to back up your log, so a new phone keeps it."
        case .notConfigured:
            return "The backup service is not set up yet. Your log stays on this phone until it is."
        case .idle(_, let summary):
            if syncManager.pendingCount > 0 {
                return "\(syncManager.pendingCount) waiting for backup."
            }
            return summary
        case .syncing:
            return nil
        case .failed(let message):
            return message
        }
    }

    private func deleteAccount() {
        deleteInProgress = true
        deleteError = nil
        Task {
            do {
                try await syncManager.deleteAccount()
            } catch {
                deleteError = error.localizedDescription
            }
            deleteInProgress = false
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        Section {
            Toggle("Auto Check In Prompts", isOn: promptsBinding)
            if let settings {
                Text(settings.promptsStatusText)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            if promptsBlockedByPermission {
                Text("Location is off, so prompts cannot appear. Open the phone setting to change it.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.closedRed)
            }
        } header: {
            Text("Privacy and Location")
        }
    }

    private var promptsBlockedByPermission: Bool {
        guard let settings, settings.autoCheckInPromptsEnabled else { return false }
        return locationService.authorizationStatus == .denied
            || locationService.authorizationStatus == .restricted
    }

    private var promptsBinding: Binding<Bool> {
        Binding(
            get: { settings?.autoCheckInPromptsEnabled ?? true },
            set: { newValue in checkInManager.setPromptsEnabled(newValue) }
        )
    }

    // MARK: - Location

    /// The notifications permission line (Sprint 7): the third denied
    /// path, next to location and photos. A denied state says plainly
    /// that prompts cannot appear and points at the phone setting; it
    /// never nags, and manual check in always works without it.
    private var notificationsSection: some View {
        Section("Notifications") {
            Button(action: openSystemSettings) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notificationService.statusDescription)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                        Text("Open the phone setting to change it")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appTextSecondary)
                }
            }
            .buttonStyle(.plain)
            if notificationService.authorizationStatus == .denied {
                Text("Notifications are off, so arrival prompts cannot appear. Check in manually from Discover or Visited.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
        }
    }

    private var locationSection: some View {
        Section("Location Access") {
            Button(action: openSystemSettings) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locationService.authorizationDescription)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                        Text("Open the phone setting to change it")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appTextSecondary)
                }
            }
            .buttonStyle(.plain)
            if locationService.isAuthorized {
                Text("\(locationService.monitoredShopCount) nearby shops watched for arrival prompts.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
        }
    }

    // MARK: - Sharing

    private var sharingSection: some View {
        Section("Sharing") {
            Toggle("Share Notes By Default", isOn: shareNotesBinding)
            Text(shareNotesStatusText)
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
        }
    }

    private var shareNotesStatusText: String {
        if settings?.shareNotesByDefault == true {
            return "On, your note is included unless you remove it."
        }
        return "Off, you choose per share."
    }

    private var shareNotesBinding: Binding<Bool> {
        Binding(
            get: { settings?.shareNotesByDefault ?? false },
            set: { newValue in
                guard let settings else { return }
                settings.shareNotesByDefault = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - Directory and about

    private var directorySection: some View {
        Section("Directory") {
            Text(directoryStatusText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
        }
    }

    private var directoryStatusText: String {
        switch directoryStore.state {
        case .loading:
            return "Loading Detroit shops..."
        case .loaded(let count, let lastUpdated):
            return "\(count) Detroit shops. Updated \(mediumDate(lastUpdated))."
        case .offlineCached(let count, let lastUpdated):
            return "\(count) Detroit shops, saved. Updated \(mediumDate(lastUpdated))."
        case .empty:
            return "No shops in the directory yet."
        case .error:
            return "The directory could not load."
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Cupmarks, version 1.0")
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            Text("Working title. The final app name is still to be decided.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
            #if DEBUG
            Text("Debug build. Sample shops appear only here and never in a TestFlight build.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
            #endif
        }
    }

    private func mediumDate(_ date: Date) -> String {
        DateFormatters.mediumDate.string(from: date)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
