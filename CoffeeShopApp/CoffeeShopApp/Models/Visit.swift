import Foundation
import SwiftData

enum VisitSource: String, Codable {
    case automatic
    case manual

    var displayText: String {
        switch self {
        case .automatic: return "Checked in automatically"
        case .manual: return "Checked in manually"
        }
    }
}

/// One saved check in. The visit saves on the phone before any jogger is
/// asked for, so a closed app or dead battery can never lose it (Flow C).
/// Shop name, neighborhood, and address are stored on the visit itself so a
/// visit still reads correctly offline and even if the directory changes.
/// `shopID` links back to the directory row for maps and history.
@Model
final class Visit {
    @Attribute(.unique) var id: UUID
    var shopID: UUID
    var shopName: String
    var neighborhood: String
    var address: String
    var checkedInAt: Date
    var sourceRaw: String
    /// Memory joggers, filled in Sprint 4. All optional; a visit is complete
    /// without them.
    var rating: Int?
    var tags: [String]
    var orderText: String?
    var note: String?
    var companionIDs: [UUID]
    var photoFilename: String?
    /// True when the shop was typed in by name and is not verified directory data.
    var isUnverifiedShop: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Sync state for Sprint 6: "local", "pending", or "synced".
    var syncStateRaw: String

    init(
        id: UUID = UUID(),
        shopID: UUID,
        shopName: String,
        neighborhood: String,
        address: String,
        checkedInAt: Date = Date(),
        source: VisitSource,
        rating: Int? = nil,
        tags: [String] = [],
        orderText: String? = nil,
        note: String? = nil,
        companionIDs: [UUID] = [],
        photoFilename: String? = nil,
        isUnverifiedShop: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStateRaw: String = "local"
    ) {
        self.id = id
        self.shopID = shopID
        self.shopName = shopName
        self.neighborhood = neighborhood
        self.address = address
        self.checkedInAt = checkedInAt
        self.sourceRaw = source.rawValue
        self.rating = rating
        self.tags = tags
        self.orderText = orderText
        self.note = note
        self.companionIDs = companionIDs
        self.photoFilename = photoFilename
        self.isUnverifiedShop = isUnverifiedShop
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncStateRaw
    }

    var source: VisitSource {
        get { VisitSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// How many joggers are filled in. The Stage 3 sync merge rule keeps the
    /// version with more joggers when the same shop on the same date merges.
    var joggerCount: Int {
        var count = 0
        if rating != nil { count += 1 }
        if !tags.isEmpty { count += 1 }
        if orderText?.isEmpty == false { count += 1 }
        if note?.isEmpty == false { count += 1 }
        if !companionIDs.isEmpty { count += 1 }
        if photoFilename != nil { count += 1 }
        return count
    }
}
