import Foundation
import Testing
import CoreLocation
@testable import CoffeeShopApp

/// Discover search and filters (Stories S2 and S3). The same pure function
/// drives the map and the list, so these tests cover both views.
struct ShopFilterTests {
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

    private static func makeShop(
        name: String,
        neighborhood: String,
        kind: ShopKind,
        hours: WeeklyHours,
        latitude: Double = 42.3314,
        longitude: Double = -83.0458
    ) -> Shop {
        Shop(
            id: UUID(),
            name: name,
            address: "1 Test Street",
            neighborhood: neighborhood,
            latitude: latitude,
            longitude: longitude,
            kind: kind,
            hours: hours,
            source: "Test fixture",
            lastVerifiedDate: Date()
        )
    }

    private static var openAllDay: WeeklyHours {
        WeeklyHours(
            mon: DayHours(open: "06:00", close: "22:00"),
            tue: DayHours(open: "06:00", close: "22:00"),
            wed: DayHours(open: "06:00", close: "22:00"),
            thu: DayHours(open: "06:00", close: "22:00"),
            fri: DayHours(open: "06:00", close: "22:00"),
            sat: DayHours(open: "06:00", close: "22:00"),
            sun: DayHours(open: "06:00", close: "22:00")
        )
    }

    private static var morningOnly: WeeklyHours {
        WeeklyHours(
            mon: DayHours(open: "07:00", close: "12:00"),
            tue: DayHours(open: "07:00", close: "12:00"),
            wed: DayHours(open: "07:00", close: "12:00"),
            thu: DayHours(open: "07:00", close: "12:00"),
            fri: DayHours(open: "07:00", close: "12:00"),
            sat: DayHours(open: "07:00", close: "12:00"),
            sun: DayHours(open: "07:00", close: "12:00")
        )
    }

    private static var fixtures: [Shop] {
        [
            Self.makeShop(name: "Midtown Roasters", neighborhood: "Midtown", kind: .independent, hours: Self.openAllDay),
            Self.makeShop(name: "Corktown Chain", neighborhood: "Corktown", kind: .chain, hours: Self.openAllDay),
            Self.makeShop(name: "Morning Cup", neighborhood: "Midtown", kind: .independent, hours: Self.morningOnly),
        ]
    }

    @Test func searchByName() {
        let results = ShopFilter.apply(Self.fixtures, criteria: ShopFilterCriteria(searchText: "roasters"))
        #expect(results.count == 1)
        #expect(results.first?.name == "Midtown Roasters")
    }

    @Test func searchByNeighborhood() {
        let results = ShopFilter.apply(Self.fixtures, criteria: ShopFilterCriteria(searchText: "midtown"))
        #expect(results.count == 2)
    }

    @Test func openNowHidesClosedShops() {
        // Wednesday Nov 18, 3 pm: Morning Cup closed at noon.
        let results = ShopFilter.apply(
            Self.fixtures,
            criteria: ShopFilterCriteria(openNowOnly: true),
            now: Self.date(day: 18, hour: 15)
        )
        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Morning Cup" } == false)
    }

    @Test func independentOnlyHidesChains() {
        let results = ShopFilter.apply(Self.fixtures, criteria: ShopFilterCriteria(independentOnly: true))
        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Corktown Chain" } == false)
    }

    @Test func neighborhoodFilter() {
        let results = ShopFilter.apply(Self.fixtures, criteria: ShopFilterCriteria(neighborhood: "Corktown"))
        #expect(results.count == 1)
        #expect(results.first?.name == "Corktown Chain")
    }

    @Test func neighborhoodsListIsSortedAndUnique() {
        #expect(ShopFilter.neighborhoods(in: Self.fixtures) == ["Corktown", "Midtown"])
    }

    @Test func nearestExcludesSampleShopsAndTheSourceShop() {
        let center = CLLocation(latitude: 42.3314, longitude: -83.0458)
        let source = Self.fixtures[0]
        let results = ShopFilter.nearest(to: center, from: Self.fixtures, excluding: source.id, limit: 5)
        #expect(results.contains { $0.id == source.id } == false)
        #expect(results.count == 2)
    }
}
