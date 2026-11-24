import Foundation
import Testing
import SwiftData
@testable import CoffeeShopApp

/// Want To Go saves (Story S12): saving from Discover and from a shared
/// recommendation, dedupe, removal, and the check in that moves a shop
/// into Visited and off Want To Go. Runs against an in-memory store.
@MainActor
struct WantToGoTests {
    private func makeStores() throws -> (WantToGoStore, VisitStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([Shop.self, Visit.self, WantToGoEntry.self, Companion.self, DismissedArrival.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (WantToGoStore(context: context), VisitStore(context: context), context)
    }

    private func makeShop() -> Shop {
        Shop(
            id: UUID(),
            name: "Test Coffee",
            address: "1 Test Street",
            neighborhood: "Midtown",
            latitude: 42.3314,
            longitude: -83.0458,
            kind: .independent,
            hours: .empty,
            source: "Test fixture",
            lastVerifiedDate: Date()
        )
    }

    @Test func saveFromDiscoverCreatesOneEntry() throws {
        let (store, _, context) = try makeStores()
        let shop = makeShop()
        context.insert(shop)
        let entry = store.save(shop: shop)
        #expect(entry.shopName == "Test Coffee")
        #expect(entry.sharedBy == nil)
        #expect(store.isSaved(shopID: shop.id))
        #expect(store.entries().count == 1)
    }

    @Test func savingTheSameShopTwiceDoesNotDuplicate() throws {
        let (store, _, context) = try makeStores()
        let shop = makeShop()
        context.insert(shop)
        let first = store.save(shop: shop)
        let second = store.save(shop: shop)
        #expect(first.id == second.id)
        #expect(store.entries().count == 1)
    }

    @Test func saveSharedKeepsTheSharerAndNote() throws {
        let (store, _, _) = try makeStores()
        let payload = SharedShopPayload(
            name: "Shared Shop",
            address: "5 Friend Avenue",
            neighborhood: "Corktown",
            rating: 5,
            note: "quiet, good for working",
            sharedBy: "Risha"
        )
        let entry = store.saveShared(payload)
        #expect(entry.shopName == "Shared Shop")
        #expect(entry.sharedBy == "Risha")
        #expect(entry.noteFromSharer == "quiet, good for working")
        #expect(store.entries().count == 1)
    }

    @Test func savingTheSameShareTwiceDoesNotDuplicate() throws {
        let (store, _, _) = try makeStores()
        let payload = SharedShopPayload(
            name: "Shared Shop",
            address: "5 Friend Avenue",
            neighborhood: "Corktown",
            sharedBy: "Risha"
        )
        let first = store.saveShared(payload)
        let second = store.saveShared(payload)
        #expect(first.id == second.id)
        #expect(store.entries().count == 1)
    }

    @Test func removeDeletesTheEntry() throws {
        let (store, _, context) = try makeStores()
        let shop = makeShop()
        context.insert(shop)
        let entry = store.save(shop: shop)
        #expect(store.entries().count == 1)
        store.remove(entry)
        #expect(store.entries().isEmpty)
        #expect(!store.isSaved(shopID: shop.id))
    }

    @Test func entriesListNewestFirst() throws {
        let (store, _, context) = try makeStores()
        let older = WantToGoEntry(
            shopID: UUID(),
            shopName: "Older Shop",
            neighborhood: "Downtown",
            address: "1 Old Road",
            addedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
        let newer = WantToGoEntry(
            shopID: UUID(),
            shopName: "Newer Shop",
            neighborhood: "Midtown",
            address: "2 New Road",
            addedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()
        let listed = store.entries()
        #expect(listed.count == 2)
        #expect(listed.first?.shopName == "Newer Shop")
        #expect(listed.last?.shopName == "Older Shop")
    }

    @Test func checkInMovesTheShopIntoVisitedAndOffWantToGo() throws {
        let (wantToGo, visitStore, context) = try makeStores()
        let shop = makeShop()
        context.insert(shop)
        _ = wantToGo.save(shop: shop)
        #expect(wantToGo.entries().count == 1)

        // The same two steps CheckInManager.checkInFromWantToGo runs:
        // save the visit first, then remove the entry.
        let result = try visitStore.saveCheckIn(shop: shop, at: Date(), source: .manual)
        #expect(result.wasDuplicate == false)
        wantToGo.remove(forShopID: shop.id)

        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 1)
        #expect(wantToGo.entries().isEmpty)
    }
}
