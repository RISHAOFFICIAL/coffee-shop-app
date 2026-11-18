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
        let shop = Shop(
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
        return visit
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

/// Central Detroit, used when location is unavailable (Flow B step 1) and
/// as the fallback coordinate for a typed in shop with no location.
enum DetroitCenter {
    static let coordinate = CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458)
}
