import Foundation
import Testing
import SwiftData
@testable import CoffeeShopApp

/// Delete with Undo (Sprint 6, Story S13): deleting a backed up visit
/// leaves a tombstone so the next sync removes it from the backup too,
/// deleting a local-only visit leaves nothing behind, and Undo restores
/// the visit whole with the same id. The orphan photo cleanup removes
/// files no visit references, including stale drafts.
@MainActor
struct VisitDeletionTests {
    private func makeStore() throws -> (VisitStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([Shop.self, Visit.self, Companion.self, DismissedArrival.self, SyncedDeletion.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (VisitStore(context: context), context)
    }

    private func makeShop() -> Shop {
        Shop(
            id: UUID(),
            name: "Test Coffee",
            address: "1 Test Street",
            neighborhood: "Midtown",
            latitude: 42.3314,
            longitude: -83.0458,
            kind: .independent,
            hours: .empty,
            source: "Test fixture",
            lastVerifiedDate: Date()
        )
    }

    private func savedVisit(in store: VisitStore, synced: Bool, context: ModelContext) throws -> Visit {
        let shop = makeShop()
        context.insert(shop)
        let result = try store.saveCheckIn(shop: shop, source: .manual)
        let visit = result.visit
        visit.rating = 5
        visit.tags = ["Cozy"]
        visit.orderText = "Latte"
        if synced {
            visit.syncState = .synced
        }
        return visit
    }

    private func tombstones(in context: ModelContext) -> [SyncedDeletion] {
        SyncedDeletion.all(in: context)
    }

    private func visits(in context: ModelContext) throws -> [Visit] {
        try context.fetch(FetchDescriptor<Visit>())
    }

    @Test func deleteSyncedVisitRecordsTombstone() throws {
        let (store, context) = try makeStore()
        let visit = try savedVisit(in: store, synced: true, context: context)
        _ = try store.deleteVisit(visit)
        #expect(try visits(in: context).isEmpty)
        let tombstone = tombstones(in: context)
        #expect(tombstone.count == 1)
        #expect(tombstone.first?.recordID == visit.id)
        #expect(tombstone.first?.kind == .visit)
    }

    @Test func deleteLocalVisitRecordsNoTombstone() throws {
        let (store, context) = try makeStore()
        let visit = try savedVisit(in: store, synced: false, context: context)
        _ = try store.deleteVisit(visit)
        #expect(try visits(in: context).isEmpty)
        #expect(tombstones(in: context).isEmpty)
    }

    @Test func undoRestoresSameVisitAndRemovesTombstone() throws {
        let (store, context) = try makeStore()
        let visit = try savedVisit(in: store, synced: true, context: context)
        let snapshot = try store.deleteVisit(visit)
        #expect(tombstones(in: context).count == 1)
        try store.restoreVisit(from: snapshot)
        let restored = try visits(in: context)
        #expect(restored.count == 1)
        #expect(restored.first?.id == visit.id)
        #expect(restored.first?.rating == 5)
        #expect(restored.first?.tags == ["Cozy"])
        #expect(restored.first?.orderText == "Latte")
        #expect(restored.first?.syncState == .synced)
        #expect(tombstones(in: context).isEmpty)
    }

    @Test func snapshotKeepsShopAndDate() throws {
        let (store, _) = try makeStore()
        let visit = try savedVisit(in: store, synced: false, context: context)
        let snapshot = try store.deleteVisit(visit)
        #expect(snapshot.shopName == "Test Coffee")
        #expect(snapshot.checkedInAt == visit.checkedInAt)
        #expect(snapshot.wasSynced == false)
    }

    @Test func tombstoneRecordingIsIdempotent() throws {
        let (store, context) = try makeStore()
        let visit = try savedVisit(in: store, synced: true, context: context)
        SyncedDeletion.record(recordID: visit.id, kind: .visit, in: context)
        SyncedDeletion.record(recordID: visit.id, kind: .visit, in: context)
        #expect(tombstones(in: context).count == 1)
    }

    @Test func orphanPhotoCleanupRemovesUnreferencedFiles() throws {
        let (store, context) = try makeStore()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisitDeletionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let visit = try savedVisit(in: store, synced: false, context: context)
        let kept = try VisitPhotoStore.saveData(Data([1, 2, 3]), for: visit.id, baseURL: base)
        visit.photoFilename = kept
        let orphan = try VisitPhotoStore.saveData(Data([4, 5, 6]), for: UUID(), baseURL: base)
        let draft = VisitPhotoStore.draftFilename(for: UUID())
        try Data([7]).write(to: base.appendingPathComponent("VisitPhotos").appendingPathComponent(draft))
        #expect(VisitPhotoStore.allFilenames(baseURL: base).count == 3)
        store.cleanupOrphanedPhotos(baseURL: base)
        let remaining = VisitPhotoStore.allFilenames(baseURL: base)
        #expect(remaining == [kept])
        #expect(!remaining.contains(orphan))
        #expect(!remaining.contains(draft))
    }
}
