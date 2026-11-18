import Foundation
import Testing
import SwiftData
import CoreLocation
@testable import CoffeeShopApp

/// Check in saving, same day duplicate protection, and dismissal records
/// (Stories S5, S6, S7). Runs against an in-memory SwiftData store.
@MainActor
struct VisitStoreTests {
    private func makeStore() throws -> (VisitStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([Shop.self, Visit.self, DismissedArrival.self]),
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

    private static var detroitCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        return Self.detroitCalendar.date(from: components)!
    }

    @Test func firstCheckInSaves() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let result = try store.saveCheckIn(shop: shop, at: date(day: 18, hour: 10), source: .manual)
        #expect(result.wasDuplicate == false)
        #expect(result.visit.shopName == "Test Coffee")
        #expect(result.visit.neighborhood == "Midtown")
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 1)
    }

    @Test func secondCheckInSameDayReturnsExistingVisit() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let first = try store.saveCheckIn(shop: shop, at: date(day: 18, hour: 10), source: .automatic)
        let second = try store.saveCheckIn(shop: shop, at: date(day: 18, hour: 15), source: .manual)
        #expect(second.wasDuplicate == true)
        #expect(second.visit.id == first.visit.id)
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 1)
    }

    @Test func checkInOnAnotherDaySavesANewVisit() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        _ = try store.saveCheckIn(shop: shop, at: date(day: 18, hour: 10), source: .manual)
        let nextDay = try store.saveCheckIn(shop: shop, at: date(day: 19, hour: 10), source: .manual)
        #expect(nextDay.wasDuplicate == false)
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 2)
    }

    @Test func unverifiedVisitIsFlagged() throws {
        let (store, context) = try makeStore()
        let visit = try store.saveUnverifiedVisit(
            name: "Typed In Shop",
            address: "Somewhere in Detroit",
            neighborhood: "Downtown",
            coordinate: CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458)
        )
        #expect(visit.isUnverifiedShop == true)
        #expect(visit.shopName == "Typed In Shop")
        let shops = try context.fetch(FetchDescriptor<Shop>())
        #expect(shops.count == 1)
        #expect(shops.first?.isUserEntered == true)
        #expect(shops.first?.isPublished == false)
    }

    @Test func dismissalAppearsInRecoveryCardForToday() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        store.recordDismissal(shop: shop, at: Date())
        let todays = store.todaysDismissals()
        #expect(todays.count == 1)
        #expect(todays.first?.shopName == "Test Coffee")
    }

    @Test func checkInClearsTheDismissal() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        store.recordDismissal(shop: shop, at: Date())
        #expect(store.todaysDismissals().count == 1)
        _ = try store.saveCheckIn(shop: shop, at: Date(), source: .manual)
        #expect(store.todaysDismissals().count == 0)
    }
}
