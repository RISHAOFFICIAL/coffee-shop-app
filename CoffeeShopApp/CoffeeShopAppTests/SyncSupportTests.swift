import Foundation
import Testing
@testable import CoffeeShopApp

/// The Stage 3 sync merge rule (Sprint 6 uses it; Sprint 1 writes it so
/// the models and the sync design agree from the start).
struct SyncSupportTests {
    private static var detroitCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        return calendar
    }

    private static func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        return Self.detroitCalendar.date(from: components)!
    }

    private static func makeVisit(shopID: UUID, day: Int, joggers: Int) -> Visit {
        let visit = Visit(
            shopID: shopID,
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            checkedInAt: Self.date(day: day, hour: 10),
            source: .manual
        )
        if joggers >= 1 { visit.rating = 5 }
        if joggers >= 2 { visit.tags = ["Cozy"] }
        if joggers >= 3 { visit.orderText = "Latte" }
        return visit
    }

    @Test func sameShopSameDayMergesIntoOne() {
        let shopID = UUID()
        let local = [Self.makeVisit(shopID: shopID, day: 18, joggers: 0)]
        let remote = [Self.makeVisit(shopID: shopID, day: 18, joggers: 0)]
        let result = VisitMerge.merge(local: local, remote: remote, calendar: Self.detroitCalendar)
        #expect(result.merged.count == 1)
        #expect(result.duplicatesMerged == 1)
    }

    @Test func versionWithMoreJoggersWins() {
        let shopID = UUID()
        let local = [Self.makeVisit(shopID: shopID, day: 18, joggers: 0)]
        let remote = [Self.makeVisit(shopID: shopID, day: 18, joggers: 3)]
        let result = VisitMerge.merge(local: local, remote: remote, calendar: Self.detroitCalendar)
        #expect(result.merged.count == 1)
        #expect(result.merged.first?.joggerCount == 3)
    }

    @Test func differentDaysStaySeparate() {
        let shopID = UUID()
        let local = [Self.makeVisit(shopID: shopID, day: 18, joggers: 0)]
        let remote = [Self.makeVisit(shopID: shopID, day: 19, joggers: 0)]
        let result = VisitMerge.merge(local: local, remote: remote, calendar: Self.detroitCalendar)
        #expect(result.merged.count == 2)
        #expect(result.duplicatesMerged == 0)
    }

    @Test func differentShopsStaySeparate() {
        let local = [Self.makeVisit(shopID: UUID(), day: 18, joggers: 0)]
        let remote = [Self.makeVisit(shopID: UUID(), day: 18, joggers: 0)]
        let result = VisitMerge.merge(local: local, remote: remote, calendar: Self.detroitCalendar)
        #expect(result.merged.count == 2)
        #expect(result.duplicatesMerged == 0)
    }

    @Test func confirmationLineCountsMerges() {
        #expect(VisitMerge.confirmationLine(backedUp: 12, duplicatesMerged: 0) == "12 visits backed up.")
        #expect(VisitMerge.confirmationLine(backedUp: 12, duplicatesMerged: 1) == "12 visits backed up, 1 duplicate merged.")
        #expect(VisitMerge.confirmationLine(backedUp: 12, duplicatesMerged: 2) == "12 visits backed up, 2 duplicates merged.")
    }
}
