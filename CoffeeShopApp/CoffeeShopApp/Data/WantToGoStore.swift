import Foundation
import SwiftData

/// Saves and removes Want To Go entries (Story S12). A shop lands here
/// from a shared recommendation or from Discover, and only a check in
/// moves it into Visited: saving never creates a visit, and this store
/// never touches the Visited list except by removing the entry after a
/// check in, which CheckInManager drives.
@MainActor
final class WantToGoStore: ObservableObject {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The entry for a shop id, if one is saved.
    func entry(forShopID shopID: UUID) -> WantToGoEntry? {
        let descriptor = FetchDescriptor<WantToGoEntry>(
            predicate: #Predicate { $0.shopID == shopID }
        )
        return try? context.fetch(descriptor).first
    }

    func isSaved(shopID: UUID) -> Bool {
        entry(forShopID: shopID) != nil
    }

    /// Every saved entry, newest first.
    func entries() -> [WantToGoEntry] {
        let all = (try? context.fetch(FetchDescriptor<WantToGoEntry>())) ?? []
        return all.sorted { $0.addedAt > $1.addedAt }
    }

    /// Saves a directory shop from Discover. Saving the same shop twice
    /// returns the existing entry; there is never a duplicate.
    @discardableResult
    func save(shop: Shop) -> WantToGoEntry {
        if let existing = entry(forShopID: shop.id) {
            return existing
        }
        let entry = WantToGoEntry(
            shopID: shop.id,
            shopName: shop.name,
            neighborhood: shop.neighborhood,
            address: shop.address
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Saves a shop from a shared recommendation (Screen 14). The sharer
    /// and their note are kept on the entry so the card can say who sent
    /// it. A directory shop dedupes by id; a shop outside the directory
    /// dedupes by name and address, so the same share twice still saves
    /// once. The entry keeps the sender's shop id when there is one, so a
    /// later directory match can still light up hours and distance.
    @discardableResult
    func saveShared(_ payload: SharedShopPayload) -> WantToGoEntry {
        if let shopID = payload.shopID, let existing = entry(forShopID: shopID) {
            return existing
        }
        let nameKey = payload.name.lowercased()
        let addressKey = payload.address.lowercased()
        if let existing = entries().first(where: {
            $0.shopName.lowercased() == nameKey && $0.address.lowercased() == addressKey
        }) {
            return existing
        }
        let entry = WantToGoEntry(
            shopID: payload.shopID ?? UUID(),
            shopName: payload.name,
            neighborhood: payload.neighborhood,
            address: payload.address,
            sharedBy: payload.sharedBy,
            noteFromSharer: payload.note
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Removes one entry. Used by the save toggle, the list swipe, and
    /// the check in from Want To Go, which moves the shop into Visited.
    func remove(_ entry: WantToGoEntry) {
        context.delete(entry)
        try? context.save()
    }

    /// Removes the entry for a shop id, if one is saved. No-op otherwise.
    func remove(forShopID shopID: UUID) {
        if let entry = entry(forShopID: shopID) {
            remove(entry)
        }
    }
}
