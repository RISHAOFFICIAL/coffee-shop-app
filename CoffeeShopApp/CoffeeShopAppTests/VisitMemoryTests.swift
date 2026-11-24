import Foundation
import Testing
import SwiftData
import UIKit
@testable import CoffeeShopApp

/// Memory joggers and visit editing (Stories S8 and S15): companion
/// find or create, jogger updates, shop correction on an existing visit,
/// and on device photo storage. Runs against an in-memory SwiftData
/// store and a temporary photo folder.
@MainActor
struct VisitMemoryTests {
    private func makeStore() throws -> (VisitStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([Shop.self, Visit.self, Companion.self, DismissedArrival.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (VisitStore(context: context), context)
    }

    private func makeShop(name: String = "Test Coffee") -> Shop {
        Shop(
            id: UUID(),
            name: name,
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

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        // Scale 1: the pixel size is the point size, so the saved JPEG
        // round trips at exactly these dimensions. The default renderer
        // format uses the device scale (3x on this simulator), which
        // would triple every dimension on load.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func tempPhotoBase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Companions

    @Test func companionFindOrCreateDedupesIgnoringCase() throws {
        let (store, context) = try makeStore()
        let first = store.companion(named: "Maya")
        let second = store.companion(named: "maya")
        let third = store.companion(named: "  Maya  ")
        #expect(first != nil)
        #expect(second?.id == first?.id)
        #expect(third?.id == first?.id)
        #expect(try context.fetchCount(FetchDescriptor<Companion>()) == 1)
        #expect(store.companion(named: "   ") == nil)
    }

    @Test func savedCompanionsAreAlphabetical() throws {
        let (store, _) = try makeStore()
        _ = store.companion(named: "Zoe")
        _ = store.companion(named: "Andre")
        _ = store.companion(named: "Maya")
        #expect(store.savedCompanions().map(\.name) == ["Andre", "Maya", "Zoe"])
    }

    // MARK: - Jogger updates

    @Test func updateMemoryAppliesEveryJogger() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let visit = try store.saveCheckIn(shop: shop, source: .manual).visit
        try store.updateMemory(
            for: visit,
            rating: 5,
            tags: ["Cozy", "cozy", " Quiet "],
            orderText: " Oat latte ",
            note: "  Best corner table. ",
            companionNames: ["Maya", "maya", "  ", "Andre"],
            photoFilename: "some-photo.jpg"
        )
        let saved = try context.fetch(FetchDescriptor<Visit>()).first
        #expect(saved?.rating == 5)
        #expect(saved?.tags == ["Cozy", "Quiet"])
        #expect(saved?.orderText == "Oat latte")
        #expect(saved?.note == "Best corner table.")
        #expect(saved?.companionIDs.count == 2)
        #expect(saved?.photoFilename == "some-photo.jpg")
        #expect(saved?.joggerCount == 6)
    }

    @Test func updateMemoryTreatsBlankTextAsNoJogger() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let visit = try store.saveCheckIn(shop: shop, source: .manual).visit
        try store.updateMemory(
            for: visit,
            rating: nil,
            tags: ["  ", ""],
            orderText: "   ",
            note: "",
            companionNames: [],
            photoFilename: nil
        )
        let saved = try context.fetch(FetchDescriptor<Visit>()).first
        #expect(saved?.rating == nil)
        #expect(saved?.tags == [])
        #expect(saved?.orderText == nil)
        #expect(saved?.note == nil)
        #expect(saved?.joggerCount == 0)
    }

    @Test func ratingIsClampedToOneThroughFive() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let visit = try store.saveCheckIn(shop: shop, source: .manual).visit
        try store.updateMemory(
            for: visit,
            rating: 9,
            tags: [],
            orderText: nil,
            note: nil,
            companionNames: [],
            photoFilename: nil
        )
        let saved = try context.fetch(FetchDescriptor<Visit>()).first
        #expect(saved?.rating == 5)
    }

    // MARK: - Visit correction (S15)

    @Test func repointVisitChangesShopWithoutCreatingAVisit() throws {
        let (store, context) = try makeStore()
        let firstShop = makeShop(name: "First Shop")
        let secondShop = makeShop(name: "Second Shop")
        context.insert(firstShop)
        context.insert(secondShop)
        let visit = try store.saveCheckIn(shop: firstShop, source: .automatic).visit
        try store.updateMemory(
            for: visit,
            rating: 4,
            tags: ["Cozy"],
            orderText: nil,
            note: nil,
            companionNames: [],
            photoFilename: nil
        )
        try store.repointVisit(visit, to: secondShop)
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 1)
        let saved = try context.fetch(FetchDescriptor<Visit>()).first
        #expect(saved?.shopID == secondShop.id)
        #expect(saved?.shopName == "Second Shop")
        #expect(saved?.isUnverifiedShop == false)
        #expect(saved?.rating == 4)
        #expect(saved?.tags == ["Cozy"])
    }

    @Test func repointVisitToTypedNameFlagsTheShopUnverified() throws {
        let (store, context) = try makeStore()
        let shop = makeShop()
        context.insert(shop)
        let visit = try store.saveCheckIn(shop: shop, source: .automatic).visit
        try store.repointVisitToTypedName(
            visit,
            name: "Typed In Shop",
            address: "Somewhere in Detroit",
            neighborhood: "Downtown",
            coordinate: nil
        )
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 1)
        let saved = try context.fetch(FetchDescriptor<Visit>()).first
        #expect(saved?.shopName == "Typed In Shop")
        #expect(saved?.isUnverifiedShop == true)
        let shops = try context.fetch(FetchDescriptor<Shop>())
        #expect(shops.count == 2)
        let typed = shops.first(where: { $0.name == "Typed In Shop" })
        #expect(typed?.isUserEntered == true)
        #expect(typed?.isPublished == false)
    }

    // MARK: - Photo storage

    @Test func photoRoundTripSavesLoadsAndDeletes() throws {
        let base = tempPhotoBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let visitID = UUID()
        let image = makeImage(width: 800, height: 600)
        let filename = try VisitPhotoStore.save(image, for: visitID, baseURL: base)
        #expect(filename == "\(visitID.uuidString).jpg")
        let loaded = VisitPhotoStore.load(filename: filename, baseURL: base)
        #expect(loaded != nil)
        #expect(loaded?.size.width == 800)
        #expect(loaded?.size.height == 600)
        VisitPhotoStore.delete(filename: filename, baseURL: base)
        #expect(VisitPhotoStore.load(filename: filename, baseURL: base) == nil)
    }

    @Test func largePhotoIsDownscaledOnSave() throws {
        let base = tempPhotoBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let visitID = UUID()
        let image = makeImage(width: 3000, height: 2000)
        let filename = try VisitPhotoStore.save(image, for: visitID, baseURL: base)
        let loaded = VisitPhotoStore.load(filename: filename, baseURL: base)
        #expect(loaded != nil)
        let longest = max(loaded?.size.width ?? 0, loaded?.size.height ?? 0)
        #expect(longest <= 1600.01)
        #expect(longest >= 1599)
    }

    @Test func draftPhotoHasItsOwnFilename() throws {
        let base = tempPhotoBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let visitID = UUID()
        let image = makeImage(width: 400, height: 300)
        let draft = try VisitPhotoStore.saveDraft(image, for: visitID, baseURL: base)
        #expect(draft == "\(visitID.uuidString)-draft.jpg")
        #expect(draft != VisitPhotoStore.filename(for: visitID))
        #expect(VisitPhotoStore.load(filename: draft, baseURL: base) != nil)
        #expect(VisitPhotoStore.load(filename: VisitPhotoStore.filename(for: visitID), baseURL: base) == nil)
    }

    @Test func missingPhotoLoadsAsNil() {
        #expect(VisitPhotoStore.load(filename: "no-such-photo.jpg", baseURL: tempPhotoBase()) == nil)
    }
}
