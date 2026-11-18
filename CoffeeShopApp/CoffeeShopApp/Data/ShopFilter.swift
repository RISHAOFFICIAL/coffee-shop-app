import Foundation
import CoreLocation

/// The Discover search and filter state (Stories S2 and S3). Pure logic,
/// so map and list can never disagree: both views filter the same array
/// through `ShopFilter.apply`.
struct ShopFilterCriteria: Equatable {
    var searchText: String = ""
    var openNowOnly: Bool = false
    var independentOnly: Bool = false
    /// Nil means all Detroit.
    var neighborhood: String? = nil

    var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || openNowOnly
            || independentOnly
            || neighborhood != nil
    }
}

enum ShopFilter {
    /// Applies search, Open Now, Independent Only, and neighborhood to one
    /// array, then sorts by distance when a location is known, otherwise by
    /// neighborhood and name (Flow B step 3).
    static func apply(
        _ shops: [Shop],
        criteria: ShopFilterCriteria,
        now: Date = Date(),
        userLocation: CLLocation? = nil
    ) -> [Shop] {
        let query = criteria.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = shops.filter { shop in
            if !query.isEmpty {
                let nameMatches = shop.name.lowercased().contains(query)
                let neighborhoodMatches = shop.neighborhood.lowercased().contains(query)
                guard nameMatches || neighborhoodMatches else { return false }
            }
            if criteria.openNowOnly {
                // Shops with unknown hours are not shown as open; the
                // detail screen says their hours are not verified yet.
                guard shop.weeklyHours.isOpen(at: now) == true else { return false }
            }
            if criteria.independentOnly {
                guard shop.kind == .independent else { return false }
            }
            if let neighborhood = criteria.neighborhood {
                guard shop.neighborhood == neighborhood else { return false }
            }
            return true
        }
        if let userLocation {
            return filtered.sorted { left, right in
                (left.distance(from: userLocation) ?? .greatestFiniteMagnitude)
                    < (right.distance(from: userLocation) ?? .greatestFiniteMagnitude)
            }
        }
        return filtered.sorted {
            if $0.neighborhood != $1.neighborhood {
                return $0.neighborhood < $1.neighborhood
            }
            return $0.name < $1.name
        }
    }

    /// Sorted neighborhood list for the filter picker.
    static func neighborhoods(in shops: [Shop]) -> [String] {
        Array(Set(shops.map(\.neighborhood))).sorted()
    }

    /// The nearest shops to a location, used by the correction list and
    /// manual check in. Sample shops are never offered for a real check in.
    static func nearest(
        to location: CLLocation,
        from shops: [Shop],
        excluding excludedID: UUID? = nil,
        limit: Int = 5
    ) -> [Shop] {
        shops
            .filter { !$0.isSample && $0.id != excludedID }
            .sorted { ($0.distance(from: location) ?? .greatestFiniteMagnitude) < ($1.distance(from: location) ?? .greatestFiniteMagnitude) }
            .prefix(limit)
            .map { $0 }
    }
}
