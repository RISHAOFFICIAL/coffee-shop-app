import Foundation
import SwiftData

/// One dismissed check in prompt. Dismissing saves nothing and the same
/// arrival never prompts again, but the quiet same day recovery card in
/// Discover and Visited lets the user log it by hand (Flow C step 7).
/// Rows older than today are cleaned up when the recovery card refreshes.
@Model
final class DismissedArrival {
    @Attribute(.unique) var id: UUID
    var shopID: UUID
    var shopName: String
    var neighborhood: String
    var dismissedAt: Date

    init(
        id: UUID = UUID(),
        shopID: UUID,
        shopName: String,
        neighborhood: String,
        dismissedAt: Date = Date()
    ) {
        self.id = id
        self.shopID = shopID
        self.shopName = shopName
        self.neighborhood = neighborhood
        self.dismissedAt = dismissedAt
    }
}
