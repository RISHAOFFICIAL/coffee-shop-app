import Foundation
import SwiftData
import CoreLocation

/// Saves check ins and owns duplicate protection and dismissal records.
/// Every save writes to SwiftData on the phone first and returns only after
/// the save completes, so the confirmation never appears before the visit
/// is safe (Flow C step 3).
@MainActor
final class VisitStore: ObservableObject {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The visit for this shop on this calendar day, if one already exists.
    func existingVisit(shopID: UUID, on date: Date, calendar: Calendar = .current) -> Visit? {
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { visit in
                visit.shopID == shopID && visit.checkedInAt >= startOfDay && visit.checkedInAt < endOfDay
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Saves a check in. When the same shop already has a visit today, no
    /// duplicate is created: the existing visit is returned with
    /// `wasDuplicate` set, and the caller opens it instead.
    @discardableResult
    func saveCheckIn(shop: Shop, at date: Date = Date(), source: VisitSource) throws -> (visit: Visit, wasDuplicate: Bool) {
        if let existing = existingVisit(shopID: shop.id, on: date) {
            return (existing, true)
        }
        let visit = Visit(
            shopID: shop.id,
            shopName: shop.name,
            neighborhood: shop.neighborhood,
            address: shop.address,
            checkedInAt: date,
            source: source,
            isUnverifiedShop: shop.isUserEntered
        )
        context.insert(visit)
        try context.save()
        removeDismissal(for: shop.id, on: date)
        notifyChanged()
        return (visit, false)
    }

    /// Saves a visit for a shop typed in by name (Flow C correction and
    /// Flow D manual check in). The shop is stored as user entered and
    /// flagged for directory review, never presented as verified data.
    @discardableResult
    func saveUnverifiedVisit(
        name: String,
        address: String,
        neighborhood: String,
        coordinate: CLLocationCoordinate2D?,
        at date: Date = Date()
    ) throws -> Visit {
        let shop = makeUnverifiedShop(
            name: name,
            address: address,
            neighborhood: neighborhood,
            coordinate: coordinate,
            at: date
        )
        context.insert(shop)
        let visit = Visit(
            shopID: shop.id,
            shopName: name,
            neighborhood: neighborhood,
            address: address,
            checkedInAt: date,
            source: .manual,
            isUnverifiedShop: true
        )
        context.insert(visit)
        try context.save()
        notifyChanged()
        return visit
    }

    /// Builds the user entered Shop row for a typed in name, shared by the
    /// check in save and the Sprint 4 visit correction. The shop is never
    /// presented as verified directory data.
    private func makeUnverifiedShop(
        name: String,
        address: String,
        neighborhood: String,
        coordinate: CLLocationCoordinate2D?,
        at date: Date
    ) -> Shop {
        Shop(
            id: UUID(),
            name: name,
            address: address,
            neighborhood: neighborhood,
            latitude: coordinate?.latitude ?? DetroitCenter.coordinate.latitude,
            longitude: coordinate?.longitude ?? DetroitCenter.coordinate.longitude,
            kind: .independent,
            hours: .empty,
            source: "Typed in by the user",
            lastVerifiedDate: date,
            isPublished: false,
            isUserEntered: true
        )
    }

    // MARK: - Memory joggers (Sprint 4, Stories S8 and S15)

    /// Every companion name saved in the app, alphabetical, for the
    /// "who was with you" picker. Contacts are never imported.
    func savedCompanions() -> [Companion] {
        let all = (try? context.fetch(FetchDescriptor<Companion>())) ?? []
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Finds the companion with this name, ignoring case, or creates one.
    /// Names are trimmed; an empty name is never saved.
    @discardableResult
    func companion(named name: String) -> Companion? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = savedCompanions().first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let companion = Companion(name: trimmed)
        context.insert(companion)
        try? context.save()
        return companion
    }

    /// Applies the joggers from the Add Memory sheet to an existing visit:
    /// rating, tags, order, note, companions, and the stored photo filename.
    /// Empty text becomes nil, tags and companion names are trimmed and
    /// deduplicated, and the visit's updated date moves to now.
    func updateMemory(
        for visit: Visit,
        rating: Int?,
        tags: [String],
        orderText: String?,
        note: String?,
        companionNames: [String],
        photoFilename: String?
    ) throws {
        visit.rating = rating.map { min(max($0, 1), 5) }
        visit.tags = Self.cleanedList(tags)
        visit.orderText = Self.cleanedText(orderText)
        visit.note = Self.cleanedText(note)
        visit.companionIDs = Self.cleanedList(companionNames)
            .compactMap { companion(named: $0)?.id }
        visit.photoFilename = photoFilename
        visit.updatedAt = Date()
        if visit.syncState == .synced {
            visit.syncState = .pending
        }
        try context.save()
        notifyChanged()
    }

    /// Points an existing visit at a different shop (Story S15, through
    /// the Sprint 3 correction path). The visit keeps its date, source,
    /// and joggers; only the shop fields change. No new visit is created.
    func repointVisit(_ visit: Visit, to shop: Shop) throws {
        visit.shopID = shop.id
        visit.shopName = shop.name
        visit.neighborhood = shop.neighborhood
        visit.address = shop.address
        visit.isUnverifiedShop = shop.isUserEntered
        visit.updatedAt = Date()
        if visit.syncState == .synced {
            visit.syncState = .pending
        }
        try context.save()
        notifyChanged()
    }

    /// Points an existing visit at a shop typed in by name. The new shop
    /// is stored as user entered and flagged unverified, the same as a
    /// typed name check in.
    func repointVisitToTypedName(
        _ visit: Visit,
        name: String,
        address: String,
        neighborhood: String,
        coordinate: CLLocationCoordinate2D?,
        at date: Date = Date()
    ) throws {
        let shop = makeUnverifiedShop(
            name: name,
            address: address,
            neighborhood: neighborhood,
            coordinate: coordinate,
            at: date
        )
        context.insert(shop)
        try repointVisit(visit, to: shop)
    }

    // MARK: - Delete with Undo (Sprint 6, Story S13)

    /// Deletes a visit and returns a snapshot the Undo bar can restore.
    /// A visit that was already backed up leaves a tombstone, so the
    /// next sync deletes it from the backup too; a local-only visit
    /// leaves nothing behind. The photo file stays until the Undo
    /// window expires; CheckInManager removes it then.
    @discardableResult
    func deleteVisit(_ visit: Visit) throws -> DeletedVisitSnapshot {
        let snapshot = DeletedVisitSnapshot(from: visit)
        if visit.syncState == .synced {
            SyncedDeletion.record(recordID: visit.id, kind: .visit, in: context)
        }
        context.delete(visit)
        try context.save()
        notifyChanged()
        return snapshot
    }

    /// Restores a visit deleted inside the Undo window, with the same
    /// id, so a synced restore does not duplicate the backup row. The
    /// tombstone is removed, so the next sync keeps the remote row.
    func restoreVisit(from snapshot: DeletedVisitSnapshot) throws {
        SyncedDeletion.remove(recordID: snapshot.id, kind: .visit, in: context)
        context.insert(snapshot.makeVisit())
        try context.save()
        notifyChanged()
    }

    /// Deletes photo files no visit references any more, including
    /// stale drafts and files from visits a sync replaced. Runs on
    /// launch, so the folder never grows without bound. Tests pass a
    /// temporary folder; the app always uses the real one.
    func cleanupOrphanedPhotos(baseURL: URL? = nil) {
        let referenced: Set<String>
        do {
            let visits = try context.fetch(FetchDescriptor<Visit>())
            referenced = Set(visits.compactMap(\.photoFilename))
        } catch {
            return
        }
        for filename in VisitPhotoStore.allFilenames(baseURL: baseURL) where !referenced.contains(filename) {
            VisitPhotoStore.delete(filename: filename, baseURL: baseURL)
        }
    }

    /// Marks every visit and Want To Go entry local again, for sign out:
    /// the next sign in backs the whole log up through the merge rule.
    func markAllLocal() {
        do {
            for visit in try context.fetch(FetchDescriptor<Visit>()) {
                visit.syncState = .local
            }
            for entry in try context.fetch(FetchDescriptor<WantToGoEntry>()) {
                entry.syncState = .local
            }
            try context.save()
        } catch {
            // Sign out must not fail on this; the records simply stay
            // marked and the next sync re-uploads them anyway.
        }
    }

    /// Tells SyncManager something changed. Local saves never wait for
    /// the network; the sync follows on its own.
    private func notifyChanged() {
        NotificationCenter.default.post(name: .coffeeShopDataChanged, object: nil)
    }

    /// Trims each entry, drops empties, and removes duplicates ignoring
    /// case, keeping the first spelling.
    private static func cleanedList(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var cleaned: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            cleaned.append(trimmed)
        }
        return cleaned
    }

    /// Trims text; an empty or whitespace only value becomes nil.
    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Dismissals and the recovery card

    func recordDismissal(shop: Shop, at date: Date = Date()) {
        let shopID = shop.id
        var descriptor = FetchDescriptor<DismissedArrival>(
            predicate: #Predicate { arrival in arrival.shopID == shopID }
        )
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return
        }
        let arrival = DismissedArrival(shopID: shop.id, shopName: shop.name, neighborhood: shop.neighborhood, dismissedAt: date)
        context.insert(arrival)
        try? context.save()
    }

    /// Today's dismissed arrivals, newest first. Older rows are cleaned up
    /// here, so the recovery card only ever shows today.
    func todaysDismissals(calendar: Calendar = .current) -> [DismissedArrival] {
        let all = (try? context.fetch(FetchDescriptor<DismissedArrival>())) ?? []
        let startOfDay = calendar.startOfDay(for: Date())
        var todays: [DismissedArrival] = []
        for arrival in all {
            if arrival.dismissedAt >= startOfDay {
                todays.append(arrival)
            } else {
                context.delete(arrival)
            }
        }
        try? context.save()
        return todays.sorted { $0.dismissedAt > $1.dismissedAt }
    }

    private func removeDismissal(for shopID: UUID, on date: Date, calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let descriptor = FetchDescriptor<DismissedArrival>(
            predicate: #Predicate { arrival in
                arrival.shopID == shopID && arrival.dismissedAt >= startOfDay && arrival.dismissedAt < endOfDay
            }
        )
        for arrival in (try? context.fetch(descriptor)) ?? [] {
            context.delete(arrival)
        }
        try? context.save()
    }
}

/// A deleted visit, kept in memory for the Undo window (Sprint 6,
/// Story S13). Plain data, not a SwiftData model, so it survives the
/// row being deleted. Restoring re-inserts the visit with the same id.
struct DeletedVisitSnapshot: Equatable {
    let id: UUID
    let shopID: UUID
    let shopName: String
    let neighborhood: String
    let address: String
    let checkedInAt: Date
    let sourceRaw: String
    let rating: Int?
    let tags: [String]
    let orderText: String?
    let note: String?
    let companionIDs: [UUID]
    let photoFilename: String?
    let isUnverifiedShop: Bool
    let createdAt: Date
    let updatedAt: Date
    let syncStateRaw: String
    /// True when the visit was backed up, so the Undo bar can say the
    /// restore brings it back to the backup too.
    let wasSynced: Bool

    init(from visit: Visit) {
        id = visit.id
        shopID = visit.shopID
        shopName = visit.shopName
        neighborhood = visit.neighborhood
        address = visit.address
        checkedInAt = visit.checkedInAt
        sourceRaw = visit.sourceRaw
        rating = visit.rating
        tags = visit.tags
        orderText = visit.orderText
        note = visit.note
        companionIDs = visit.companionIDs
        photoFilename = visit.photoFilename
        isUnverifiedShop = visit.isUnverifiedShop
        createdAt = visit.createdAt
        updatedAt = visit.updatedAt
        syncStateRaw = visit.syncStateRaw
        wasSynced = visit.syncState == .synced
    }

    func makeVisit() -> Visit {
        let visit = Visit(
            id: id,
            shopID: shopID,
            shopName: shopName,
            neighborhood: neighborhood,
            address: address,
            checkedInAt: checkedInAt,
            source: VisitSource(rawValue: sourceRaw) ?? .manual,
            isUnverifiedShop: isUnverifiedShop,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        visit.rating = rating
        visit.tags = tags
        visit.orderText = orderText
        visit.note = note
        visit.companionIDs = companionIDs
        visit.photoFilename = photoFilename
        visit.syncStateRaw = syncStateRaw
        return visit
    }
}

/// Central Detroit, used when location is unavailable (Flow B step 1) and
/// as the fallback coordinate for a typed in shop with no location.
enum DetroitCenter {
    static let coordinate = CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458)
}
