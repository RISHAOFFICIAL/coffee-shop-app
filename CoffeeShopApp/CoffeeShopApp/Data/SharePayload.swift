import Foundation
import CoreLocation

/// The shop a friend shared, carried in the message and in the app link.
/// Everything the Shared Shop Landing needs rides in the payload itself, so
/// it works even when the shared shop is not in the recipient's directory.
/// No universal link domain was approved in Sprint 0, so the landing opens
/// through the app's own URL scheme (see SharedShopLink); the HTTPS
/// universal link stays deferred to the post version 1 backlog, per the
/// build plan, and the full details always ride in the message text.
struct SharedShopPayload: Identifiable, Equatable {
    /// A directory shop id when the sender's shop is in the directory.
    /// Nil for a shop typed in by name, which has no shared id.
    var shopID: UUID?
    var name: String
    var address: String
    var neighborhood: String
    var latitude: Double?
    var longitude: Double?
    var rating: Int?
    var note: String?
    var sharedBy: String?

    var id: String { name + "|" + address + "|" + (sharedBy ?? "") }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Builds the payload for a visit being shared. The coordinate comes
    /// from the directory shop when one was found; without it the landing
    /// still works from the address.
    init(
        visit: Visit,
        coordinate: CLLocationCoordinate2D?,
        includeNote: Bool,
        sharedBy: String?
    ) {
        self.shopID = visit.isUnverifiedShop ? nil : visit.shopID
        self.name = visit.shopName
        self.address = visit.address
        self.neighborhood = visit.neighborhood
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.rating = visit.rating
        self.note = includeNote ? visit.note : nil
        let trimmedSharer = sharedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sharedBy = (trimmedSharer?.isEmpty == false) ? trimmedSharer : nil
    }

    init(
        shopID: UUID? = nil,
        name: String,
        address: String,
        neighborhood: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        rating: Int? = nil,
        note: String? = nil,
        sharedBy: String? = nil
    ) {
        self.shopID = shopID
        self.name = name
        self.address = address
        self.neighborhood = neighborhood
        self.latitude = latitude
        self.longitude = longitude
        self.rating = rating
        self.note = note
        self.sharedBy = sharedBy
    }
}

/// The app's own URL scheme, the path into the Shared Shop Landing for a
/// recipient who already has the app. A recipient without the app gets
/// nothing from this link, which is why the full details always ride in
/// the message text next to it.
enum SharedShopLink {
    static let scheme = "coffeeshopapp"
    static let host = "shared-shop"

    /// Encodes a payload into an app link, or nil when the name is blank.
    static func url(for payload: SharedShopPayload) -> URL? {
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items: [URLQueryItem] = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "address", value: payload.address),
            URLQueryItem(name: "neighborhood", value: payload.neighborhood),
        ]
        if let shopID = payload.shopID {
            items.append(URLQueryItem(name: "shop", value: shopID.uuidString))
        }
        if let latitude = payload.latitude, let longitude = payload.longitude {
            items.append(URLQueryItem(name: "lat", value: String(latitude)))
            items.append(URLQueryItem(name: "lng", value: String(longitude)))
        }
        if let rating = payload.rating {
            items.append(URLQueryItem(name: "rating", value: String(rating)))
        }
        if let note = payload.note, !note.isEmpty {
            items.append(URLQueryItem(name: "note", value: note))
        }
        if let sharedBy = payload.sharedBy, !sharedBy.isEmpty {
            items.append(URLQueryItem(name: "by", value: sharedBy))
        }
        components.queryItems = items
        return components.url
    }

    /// Decodes an app link back into a payload. Returns nil for any URL
    /// that is not one of our shared shop links, or one without a name.
    static func decode(_ url: URL) -> SharedShopPayload? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        var values: [String: String] = [:]
        for item in items {
            values[item.name] = item.value ?? ""
        }
        guard let name = values["name"], !name.isEmpty else { return nil }
        let shopID = values["shop"].flatMap(UUID.init(uuidString:))
        let latitude = values["lat"].flatMap(Double.init)
        let longitude = values["lng"].flatMap(Double.init)
        let rating = values["rating"].flatMap(Int.init).map { min(max($0, 1), 5) }
        let note = values["note"].flatMap { $0.isEmpty ? nil : $0 }
        let sharedBy = values["by"].flatMap { $0.isEmpty ? nil : $0 }
        return SharedShopPayload(
            shopID: shopID,
            name: name,
            address: values["address"] ?? "",
            neighborhood: values["neighborhood"] ?? "",
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            note: note,
            sharedBy: sharedBy
        )
    }
}

/// The text of a shared recommendation (Story S11, Flow F). The message
/// carries the complete details, so it works for a friend without the app:
/// shop name, address, neighborhood, rating, and the note when the sender
/// left it included, plus a directions link. The app link rides last, for
/// a friend who has the app.
enum ShareText {
    /// The full message for a visit, exactly as the share preview shows it.
    static func message(
        for visit: Visit,
        coordinate: CLLocationCoordinate2D?,
        includeNote: Bool,
        sharerName: String?
    ) -> String {
        let payload = SharedShopPayload(
            visit: visit,
            coordinate: coordinate,
            includeNote: includeNote,
            sharedBy: sharerName
        )
        return message(for: payload)
    }

    /// The full message for a payload, built from its own fields.
    static func message(for payload: SharedShopPayload) -> String {
        var lines: [String] = [payload.name]
        if !payload.address.isEmpty {
            lines.append(payload.address)
        }
        if !payload.neighborhood.isEmpty {
            lines.append("\(payload.neighborhood), Detroit")
        }
        if let rating = payload.rating {
            lines.append("Rated \(rating) out of 5")
        }
        if let note = payload.note, !note.isEmpty {
            lines.append("Note: \(note)")
        }
        if let mapsURL = mapsDirectionsURL(address: payload.address, name: payload.name) {
            lines.append("Directions: \(mapsURL.absoluteString)")
        }
        if let appURL = SharedShopLink.url(for: payload) {
            lines.append("Open in the Coffee Shop app: \(appURL.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    /// An Apple Maps directions link for an address. Nil when the address
    /// is blank, so the message never carries a link to nowhere.
    static func mapsDirectionsURL(address: String, name: String) -> URL? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "daddr", value: trimmedAddress)]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmedName))
        }
        components?.queryItems = items
        return components?.url
    }
}
