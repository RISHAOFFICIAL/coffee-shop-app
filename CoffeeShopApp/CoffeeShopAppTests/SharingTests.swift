import Foundation
import Testing
import CoreLocation
@testable import CoffeeShopApp

/// Sharing (Story S11): the app link round trip, the share message
/// contents, and the Maps directions link. The message is the contract:
/// it carries the complete details so a friend without the app still gets
/// a usable recommendation.
struct SharingTests {
    private func makeVisit() -> Visit {
        Visit(
            shopID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            shopName: "Sample Shop One",
            neighborhood: "Midtown",
            address: "1 Sample Street, Detroit, MI",
            checkedInAt: Date(timeIntervalSince1970: 1_790_000_000),
            source: .manual,
            rating: 5,
            tags: ["Quiet"],
            orderText: "vanilla latte",
            note: "great light in the morning"
        )
    }

    private func fullPayload() -> SharedShopPayload {
        SharedShopPayload(
            shopID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            name: "Sample Shop One",
            address: "1 Sample Street, Detroit, MI",
            neighborhood: "Midtown",
            latitude: 42.3487,
            longitude: -83.0567,
            rating: 5,
            note: "great light in the morning",
            sharedBy: "Risha"
        )
    }

    @Test func appLinkRoundTripsEveryField() throws {
        let payload = fullPayload()
        let url = try #require(SharedShopLink.url(for: payload))
        #expect(url.scheme == "coffeeshopapp")
        #expect(url.host == "shared-shop")
        let decoded = try #require(SharedShopLink.decode(url))
        #expect(decoded == payload)
    }

    @Test func appLinkRoundTripsANameOnlyPayload() throws {
        let payload = SharedShopPayload(name: "Typed In Shop", address: "", neighborhood: "")
        let url = try #require(SharedShopLink.url(for: payload))
        let decoded = try #require(SharedShopLink.decode(url))
        #expect(decoded == payload)
        #expect(decoded.shopID == nil)
        #expect(decoded.rating == nil)
    }

    @Test func decodeRejectsOtherLinks() {
        #expect(SharedShopLink.decode(URL(string: "https://example.com/shared-shop?name=X")!) == nil)
        #expect(SharedShopLink.decode(URL(string: "coffeeshopapp://other?name=X")!) == nil)
        #expect(SharedShopLink.decode(URL(string: "coffeeshopapp://shared-shop?address=Nowhere")!) == nil)
    }

    @Test func shareMessageCarriesTheCompleteDetails() {
        let message = ShareText.message(
            for: makeVisit(),
            coordinate: CLLocationCoordinate2D(latitude: 42.3487, longitude: -83.0567),
            includeNote: true,
            sharerName: "Risha"
        )
        #expect(message.contains("Sample Shop One"))
        #expect(message.contains("1 Sample Street, Detroit, MI"))
        #expect(message.contains("Midtown, Detroit"))
        #expect(message.contains("Rated 5 out of 5"))
        #expect(message.contains("Note: great light in the morning"))
        #expect(message.contains("Directions: https://maps.apple.com/"))
        #expect(message.contains("Open in the Coffee Shop app: coffeeshopapp://shared-shop?"))
    }

    @Test func shareMessageLeavesTheNoteOutWhenAsked() {
        let message = ShareText.message(
            for: makeVisit(),
            coordinate: nil,
            includeNote: false,
            sharerName: nil
        )
        #expect(message.contains("Sample Shop One"))
        #expect(message.contains("Rated 5 out of 5"))
        #expect(!message.contains("great light in the morning"))
        #expect(!message.contains("Note:"))
    }

    @Test func shareMessageSkipsTheRatingLineWhenThereIsNone() {
        let visit = Visit(
            shopID: UUID(),
            shopName: "No Rating Shop",
            neighborhood: "Downtown",
            address: "9 Nowhere Road",
            source: .manual
        )
        let message = ShareText.message(for: visit, coordinate: nil, includeNote: true, sharerName: nil)
        #expect(!message.contains("Rated"))
        #expect(message.contains("No Rating Shop"))
    }

    @Test func unverifiedVisitSharesWithoutAShopID() {
        let visit = Visit(
            shopID: UUID(),
            shopName: "Typed In Shop",
            neighborhood: "Downtown",
            address: "",
            source: .manual,
            isUnverifiedShop: true
        )
        let payload = SharedShopPayload(visit: visit, coordinate: nil, includeNote: false, sharedBy: nil)
        #expect(payload.shopID == nil)
        #expect(payload.name == "Typed In Shop")
    }

    @Test func mapsLinkIsNilForABlankAddress() {
        #expect(ShareText.mapsDirectionsURL(address: "  ", name: "Somewhere") == nil)
        let url = ShareText.mapsDirectionsURL(address: "1 Sample Street, Detroit, MI", name: "Sample Shop One")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("maps.apple.com") == true)
    }
}
