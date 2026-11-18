import Foundation
import SwiftData

/// A shop saved to Want To Go. It is not a visit: only a check in moves a
/// shop into Visited (Flow G). The full Want To Go list UI arrives in
/// Sprint 5; the model lands in Sprint 1 so saves and sync stay consistent.
@Model
final class WantToGoEntry {
    @Attribute(.unique) var id: UUID
    var shopID: UUID
    var shopName: String
    var neighborhood: String
    var address: String
    var sharedBy: String?
    var noteFromSharer: String?
    var addedAt: Date
    var updatedAt: Date
    /// Sync state for Sprint 6: "local", "pending", or "synced".
    var syncStateRaw: String

    init(
        id: UUID = UUID(),
        shopID: UUID,
        shopName: String,
        neighborhood: String,
        address: String,
        sharedBy: String? = nil,
        noteFromSharer: String? = nil,
        addedAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStateRaw: String = "local"
    ) {
        self.id = id
        self.shopID = shopID
        self.shopName = shopName
        self.neighborhood = neighborhood
        self.address = address
        self.sharedBy = sharedBy
        self.noteFromSharer = noteFromSharer
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncStateRaw
    }
}
