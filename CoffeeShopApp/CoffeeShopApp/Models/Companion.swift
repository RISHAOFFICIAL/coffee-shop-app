import Foundation
import SwiftData

/// A companion name the user typed or picked inside the app, saved so a
/// future visit can reuse it. Contacts are never imported in version 1.
@Model
final class Companion {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
