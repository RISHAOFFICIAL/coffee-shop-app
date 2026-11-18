import Foundation
import SwiftData
import CoreLocation

enum ShopKind: String, Codable {
    case independent
    case chain

    var displayText: String {
        switch self {
        case .independent: return "Independent"
        case .chain: return "Chain"
        }
    }
}

/// One coffee shop in the Detroit directory. The directory is curated data:
/// every shop carries a source and a last verified date, per the build spec.
/// The same UUID is the Supabase row id, so the on device cache and the
/// server row are the same record. User entered shops (typed names from a
/// manual check in) are flagged and never presented as verified directory data.
@Model
final class Shop {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var neighborhood: String
    var latitude: Double
    var longitude: Double
    var kindRaw: String
    /// Weekly hours as JSON, decoded through `weeklyHours`.
    var hoursJSON: String
    var tags: [String]
    var photoURL: String?
    var photoRights: String?
    var source: String
    var lastVerifiedDate: Date
    var isPublished: Bool
    /// True only for the debug sample dataset. Sample shops are compiled
    /// out of release builds entirely (see SampleData.swift).
    var isSample: Bool
    /// True for a shop typed in by the user during a manual check in.
    var isUserEntered: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        address: String,
        neighborhood: String,
        latitude: Double,
        longitude: Double,
        kind: ShopKind,
        hours: WeeklyHours,
        tags: [String] = [],
        photoURL: String? = nil,
        photoRights: String? = nil,
        source: String,
        lastVerifiedDate: Date,
        isPublished: Bool = true,
        isSample: Bool = false,
        isUserEntered: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.neighborhood = neighborhood
        self.latitude = latitude
        self.longitude = longitude
        self.kindRaw = kind.rawValue
        self.hoursJSON = (try? JSONEncoder().encode(hours)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.tags = tags
        self.photoURL = photoURL
        self.photoRights = photoRights
        self.source = source
        self.lastVerifiedDate = lastVerifiedDate
        self.isPublished = isPublished
        self.isSample = isSample
        self.isUserEntered = isUserEntered
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: ShopKind {
        get { ShopKind(rawValue: kindRaw) ?? .independent }
        set { kindRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var weeklyHours: WeeklyHours {
        get {
            guard let data = hoursJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(WeeklyHours.self, from: data) else {
                return .empty
            }
            return decoded
        }
        set {
            hoursJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }

    /// Open Now, from real hours and the phone clock. Nil when hours are unknown.
    var isOpenNow: Bool? {
        weeklyHours.isOpen(at: Date())
    }

    /// "Open Now, until 6 pm", "Closed", or "Hours not verified yet".
    var openStatusText: String {
        guard weeklyHours.hasAnyHours else { return "Hours not verified yet" }
        if isOpenNow == true {
            if let closing = weeklyHours.closingText(at: Date()) {
                return "Open Now, \(closing)"
            }
            return "Open Now"
        }
        return "Closed"
    }

    func distance(from location: CLLocation?) -> CLLocationDistance? {
        guard let location else { return nil }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    /// "0.4 mi" or nil when no location is available.
    func distanceText(from location: CLLocation?) -> String? {
        guard let distance = distance(from: location) else { return nil }
        let miles = distance / 1609.34
        if miles < 0.1 {
            return "Here"
        }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }
}

// MARK: - Directory transfer objects

/// The wire shape for a shop, matching the Supabase `shops` table and the
/// bundled batch JSON file. Dates arrive as "yyyy-MM-dd" strings and are
/// parsed in the mapper, so a bad date skips one row instead of failing
/// the whole batch.
struct ShopDTO: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var address: String
    var neighborhood: String
    var latitude: Double
    var longitude: Double
    var kind: String
    var hours: WeeklyHours = .empty
    var tags: [String] = []
    var photo_url: String?
    var photo_rights: String?
    var source: String
    var last_verified_date: String
    var is_published: Bool = true

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Builds a Shop, or returns nil when the row is unusable (bad date or
    /// bad kind). The caller counts skipped rows for the directory log.
    func toShop() -> Shop? {
        guard let verified = Self.dateFormatter.date(from: last_verified_date),
              let kind = ShopKind(rawValue: kind) else { return nil }
        // A photo reference is only kept when its rights basis is recorded,
        // matching the Supabase photo rights constraint.
        let keptPhotoURL = photo_rights == nil ? nil : photo_url
        return Shop(
            id: id,
            name: name,
            address: address,
            neighborhood: neighborhood,
            latitude: latitude,
            longitude: longitude,
            kind: kind,
            hours: hours,
            tags: tags,
            photoURL: keptPhotoURL,
            photoRights: photo_rights,
            source: source,
            lastVerifiedDate: verified,
            isPublished: is_published
        )
    }
}

/// The bundled batch file wrapper: detroit-shops-batch-1.json.
struct ShopBatchFile: Codable {
    var batch: Int
    var generated: String
    var shops: [ShopDTO]
}
