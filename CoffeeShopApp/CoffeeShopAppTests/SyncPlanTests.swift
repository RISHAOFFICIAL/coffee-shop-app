import Foundation
import Testing
@testable import CoffeeShopApp

/// The sync merge plans (Sprint 6, Story S14): what uploads, what
/// inserts, what updates, and what gets deleted, decided before any
/// network call. The Stage 3 rule holds throughout: the same shop on
/// the same day merges into one visit, never a duplicate, and the
/// version with more joggers wins.
struct SyncPlanTests {
    private static var detroitCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        return calendar
    }

    private static func date(day: Int, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        return detroitCalendar.date(from: components)!
    }

    private static func makeVisit(
        id: UUID = UUID(),
        shopID: UUID,
        day: Int,
        joggers: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Visit {
        let visit = Visit(
            id: id,
            shopID: shopID,
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            checkedInAt: date(day: day),
            source: .manual,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        if joggers >= 1 { visit.rating = 5 }
        if joggers >= 2 { visit.tags = ["Cozy"] }
        if joggers >= 3 { visit.orderText = "Latte" }
        return visit
    }

    private static func dto(for visit: Visit) -> VisitDTO {
        VisitDTO(from: visit, ownerID: UUID())
    }

    // MARK: - Visits

    @Test func remoteOnlyVisitInserts() {
        let shopID = UUID()
        let remote = dto(for: makeVisit(shopID: shopID, day: 18))
        let plan = SyncPlan.visits(local: [], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.toInsert.count == 1)
        #expect(plan.toUpload.isEmpty)
        #expect(plan.duplicatesMerged == 0)
    }

    @Test func localOnlyVisitUploads() {
        let shopID = UUID()
        let local = makeVisit(shopID: shopID, day: 18)
        let plan = SyncPlan.visits(local: [local], remote: [], calendar: Self.detroitCalendar)
        #expect(plan.toUpload.count == 1)
        #expect(plan.toInsert.isEmpty)
        #expect(plan.duplicatesMerged == 0)
    }

    @Test func sameDayDuplicateMergesWithLocalWinnerUploading() {
        let shopID = UUID()
        let local = makeVisit(shopID: shopID, day: 18, joggers: 3)
        let remote = dto(for: makeVisit(shopID: shopID, day: 18, joggers: 0))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.duplicatesMerged == 1)
        #expect(plan.toUpload.count == 1)
        #expect(plan.toUpload.first?.id == local.id)
        #expect(plan.toDeleteRemoteIDs == [remote.id])
        #expect(plan.toInsert.isEmpty)
        #expect(plan.toDeleteLocal.isEmpty)
    }

    @Test func sameDayDuplicateMergesWithRemoteWinnerInserting() {
        let shopID = UUID()
        let local = makeVisit(shopID: shopID, day: 18, joggers: 0)
        let remote = dto(for: makeVisit(shopID: shopID, day: 18, joggers: 3))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.duplicatesMerged == 1)
        #expect(plan.toInsert.count == 1)
        #expect(plan.toInsert.first?.id == remote.id)
        #expect(plan.toDeleteLocal.count == 1)
        #expect(plan.toDeleteLocal.first?.id == local.id)
        #expect(plan.toUpload.isEmpty)
        #expect(plan.toDeleteRemoteIDs.isEmpty)
    }

    @Test func sameIdNewerRemoteUpdatesLocal() {
        let id = UUID()
        let shopID = UUID()
        let local = makeVisit(id: id, shopID: shopID, day: 18, updatedAt: date(day: 18, hour: 9))
        let remote = dto(for: makeVisit(id: id, shopID: shopID, day: 18, updatedAt: date(day: 18, hour: 11)))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.toUpdateLocal.count == 1)
        #expect(plan.toUpdateLocal.first?.0.id == id)
        #expect(plan.toUpload.isEmpty)
        #expect(plan.duplicatesMerged == 0)
    }

    @Test func sameIdNewerLocalUploads() {
        let id = UUID()
        let shopID = UUID()
        let local = makeVisit(id: id, shopID: shopID, day: 18, updatedAt: date(day: 18, hour: 11))
        let remote = dto(for: makeVisit(id: id, shopID: shopID, day: 18, updatedAt: date(day: 18, hour: 9)))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.toUpload.count == 1)
        #expect(plan.toUpdateLocal.isEmpty)
        #expect(plan.duplicatesMerged == 0)
    }

    @Test func sameIdSameDateIsInSync() {
        let id = UUID()
        let shopID = UUID()
        let stamp = date(day: 18, hour: 10)
        let local = makeVisit(id: id, shopID: shopID, day: 18, updatedAt: stamp)
        let remote = dto(for: makeVisit(id: id, shopID: shopID, day: 18, updatedAt: stamp))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.toUpload.isEmpty)
        #expect(plan.toInsert.isEmpty)
        #expect(plan.toUpdateLocal.isEmpty)
        #expect(plan.duplicatesMerged == 0)
    }

    @Test func differentDaysStaySeparate() {
        let shopID = UUID()
        let local = makeVisit(shopID: shopID, day: 18)
        let remote = dto(for: makeVisit(shopID: shopID, day: 19))
        let plan = SyncPlan.visits(local: [local], remote: [remote], calendar: Self.detroitCalendar)
        #expect(plan.toUpload.count == 1)
        #expect(plan.toInsert.count == 1)
        #expect(plan.duplicatesMerged == 0)
    }

    // MARK: - Want To Go

    private static func makeEntry(
        id: UUID = UUID(),
        shopID: UUID,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> WantToGoEntry {
        WantToGoEntry(
            id: id,
            shopID: shopID,
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            addedAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    @Test func wantToGoMergesByShopID() {
        let shopID = UUID()
        let local = makeEntry(shopID: shopID, updatedAt: date(day: 18, hour: 9))
        let remote = WantToGoDTO(
            from: makeEntry(shopID: shopID, updatedAt: date(day: 18, hour: 11)),
            ownerID: UUID()
        )
        let plan = SyncPlan.wantToGo(local: [local], remote: [remote])
        #expect(plan.toUpdateLocal.count == 1)
        #expect(plan.toUpload.isEmpty)
    }

    @Test func wantToGoLocalOnlyUploadsAndRemoteOnlyInserts() {
        let local = makeEntry(shopID: UUID())
        let remote = WantToGoDTO(from: makeEntry(shopID: UUID()), ownerID: UUID())
        let plan = SyncPlan.wantToGo(local: [local], remote: [remote])
        #expect(plan.toUpload.count == 1)
        #expect(plan.toInsert.count == 1)
        #expect(plan.toUpdateLocal.isEmpty)
    }

    @Test func wantToGoNewerLocalUploadsAndDeletesRemoteCopy() {
        let shopID = UUID()
        let local = makeEntry(shopID: shopID, updatedAt: date(day: 18, hour: 11))
        let remote = WantToGoDTO(
            from: makeEntry(shopID: shopID, updatedAt: date(day: 18, hour: 9)),
            ownerID: UUID()
        )
        let plan = SyncPlan.wantToGo(local: [local], remote: [remote])
        #expect(plan.toUpload.count == 1)
        #expect(plan.toDeleteRemoteIDs == [remote.id])
    }

    // MARK: - Companions

    @Test func companionPlanRemapsByName() {
        let local = Companion(name: "Aric")
        let remote = CompanionDTO(from: Companion(name: "aric"), ownerID: UUID())
        let plan = SyncPlan.companions(local: [local], remote: [remote])
        #expect(plan.toInsert.isEmpty)
        #expect(plan.toUpload.isEmpty)
        #expect(plan.remapIDs[remote.id] == local.id)
    }

    @Test func companionPlanInsertsRemoteOnlyAndUploadsLocalOnly() {
        let local = Companion(name: "Aric")
        let remote = CompanionDTO(from: Companion(name: "Bella"), ownerID: UUID())
        let plan = SyncPlan.companions(local: [local], remote: [remote])
        #expect(plan.toInsert.count == 1)
        #expect(plan.toUpload.count == 1)
        #expect(plan.remapIDs.isEmpty)
    }

    // MARK: - Settings

    @Test func settingsPlanComparesUpdatedAt() {
        let settings = UserSettings(updatedAt: date(day: 18, hour: 10))
        let ownerID = UUID()
        #expect(SyncPlan.settings(local: settings, remote: nil) == .uploadLocal)
        let newerRemote = UserSettingsDTO(from: UserSettings(updatedAt: date(day: 18, hour: 11)), userID: ownerID)
        #expect(SyncPlan.settings(local: settings, remote: newerRemote) == .applyRemote(newerRemote))
        let olderRemote = UserSettingsDTO(from: UserSettings(updatedAt: date(day: 18, hour: 9)), userID: ownerID)
        #expect(SyncPlan.settings(local: settings, remote: olderRemote) == .uploadLocalNewer)
        let sameRemote = UserSettingsDTO(from: UserSettings(updatedAt: date(day: 18, hour: 10)), userID: ownerID)
        #expect(SyncPlan.settings(local: settings, remote: sameRemote) == .inSync)
    }
}
