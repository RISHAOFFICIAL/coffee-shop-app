import Foundation
import Testing
import UIKit
@testable import CoffeeShopApp

/// Sprint 7 hardening and accessibility: the filter descriptions the no
/// results states show, the share link note cap, the shared date
/// formatters, and the photo thumbnail loader. Runs against plain values
/// and a temporary photo folder; no SwiftData store is needed.
@MainActor
struct HardeningTests {
    // MARK: - Discover filter descriptions (ShopFilterCriteria)

    @Test func noFiltersHasNoDescription() {
        #expect(ShopFilterCriteria().activeFiltersDescription == nil)
    }

    @Test func searchTextAloneIsNotAFilter() {
        // The search text stays visible in the search field; the
        // description only names the filters.
        let criteria = ShopFilterCriteria(searchText: "latte")
        #expect(criteria.activeFiltersDescription == nil)
    }

    @Test func openNowOnlyDescribesItself() {
        let criteria = ShopFilterCriteria(openNowOnly: true)
        #expect(criteria.activeFiltersDescription == "Open Now")
    }

    @Test func allFiltersDescribeInOrder() {
        let criteria = ShopFilterCriteria(
            openNowOnly: true,
            independentOnly: true,
            neighborhood: "Downtown"
        )
        #expect(criteria.activeFiltersDescription == "Open Now, Independent Only, Downtown")
    }

    // MARK: - Visited search filter descriptions (VisitedSearchFilters)

    @Test func noVisitedFiltersHasNoDescription() {
        #expect(VisitedSearchFilters().activeFiltersDescription(namesByID: [:]) == nil)
    }

    @Test func visitedTagsDescribeAlphabetically() {
        var filters = VisitedSearchFilters()
        filters.tags = ["Quiet", "Cozy"]
        #expect(filters.activeFiltersDescription(namesByID: [:]) == "Cozy, Quiet")
    }

    @Test func visitedFiltersCombineInGroups() {
        let mayaID = UUID()
        var filters = VisitedSearchFilters()
        filters.tags = ["Cozy"]
        filters.neighborhoods = ["Downtown"]
        filters.companionIDs = [mayaID]
        filters.ratings = [5]
        let description = filters.activeFiltersDescription(namesByID: [mayaID: "Maya"])
        #expect(description == "Cozy, Downtown, with Maya, 5 stars")
    }

    @Test func visitedFilterSkipsACompanionWithNoName() {
        // A companion id whose row is gone never shows as a blank filter.
        var filters = VisitedSearchFilters()
        filters.companionIDs = [UUID()]
        #expect(filters.activeFiltersDescription(namesByID: [:]) == nil)
    }

    // MARK: - Share link note cap (SharedShopLink)

    @Test func longNoteIsCappedInTheLink() {
        let longNote = String(repeating: "a", count: 600)
        let payload = SharedShopPayload(
            name: "Test Coffee",
            address: "1 Test Street",
            neighborhood: "Midtown",
            note: longNote
        )
        let url = SharedShopLink.url(for: payload)
        #expect(url != nil)
        let decoded = url.flatMap(SharedShopLink.decode)
        #expect(decoded?.note?.count == SharedShopLink.linkNoteLimit)
    }

    @Test func shortNoteSurvivesTheLinkUnchanged() {
        let payload = SharedShopPayload(
            name: "Test Coffee",
            address: "1 Test Street",
            neighborhood: "Midtown",
            note: "Best latte in town"
        )
        let decoded = SharedShopLink.url(for: payload).flatMap(SharedShopLink.decode)
        #expect(decoded?.note == "Best latte in town")
    }

    @Test func messageStillCarriesTheFullNote() {
        // The cap is only for the link. The message text next to it
        // always carries the whole note.
        let longNote = String(repeating: "b", count: 600)
        let payload = SharedShopPayload(
            name: "Test Coffee",
            address: "1 Test Street",
            neighborhood: "Midtown",
            note: longNote
        )
        #expect(ShareText.message(for: payload).contains(longNote))
    }

    // MARK: - Shared date formatters (DateFormatters)

    /// Nov 23, 2026, 3:30 PM UTC, as a fixed timestamp. The formatted
    /// time of day shifts with the test host's time zone, so the tests
    /// only assert on the year and the presence of a time.
    private func knownDate() -> Date {
        Date(timeIntervalSince1970: 1_795_447_800)
    }

    @Test func mediumDateFormatsWithoutATime() {
        let text = DateFormatters.mediumDate.string(from: knownDate())
        #expect(text.contains("2026"))
        #expect(!text.contains(":"))
    }

    @Test func mediumDateShortTimeFormatsWithATime() {
        let text = DateFormatters.mediumDateShortTime.string(from: knownDate())
        #expect(text.contains("2026"))
        #expect(text.contains(":"))
    }

    @Test func fullDateShortTimeFormats() {
        let text = DateFormatters.fullDateShortTime.string(from: knownDate())
        #expect(text.contains("2026"))
        #expect(text.contains(":"))
    }

    @Test func formattersAreSharedInstances() {
        // The point of the shared formatters is that the same instance
        // is reused, instead of one built per render.
        #expect(DateFormatters.mediumDate === DateFormatters.mediumDate)
        #expect(DateFormatters.mediumDateShortTime === DateFormatters.mediumDateShortTime)
        #expect(DateFormatters.fullDateShortTime === DateFormatters.fullDateShortTime)
    }

    // MARK: - Photo thumbnails (VisitPhotoStore)

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in
            UIColor.brown.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makeTempFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func photoDirectoryEndsWithVisitPhotos() {
        #expect(VisitPhotoStore.directoryURL().lastPathComponent == "VisitPhotos")
    }

    @Test func thumbnailShrinksALargePhoto() throws {
        let folder = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let visitID = UUID()
        let filename = try VisitPhotoStore.save(makeImage(width: 2000, height: 1000), for: visitID, baseURL: folder)
        let thumbnail = VisitPhotoStore.thumbnail(filename: filename, baseURL: folder)
        #expect(thumbnail != nil)
        // 2000x1000 at a 112pt long edge keeps its 2:1 aspect ratio.
        // Ranges, not exact sizes: the scale math is floating point.
        let longest = max(thumbnail?.size.width ?? 0, thumbnail?.size.height ?? 0)
        #expect(longest <= 112.01)
        #expect(longest >= 111)
        let ratio = (thumbnail?.size.width ?? 0) / (thumbnail?.size.height ?? 1)
        #expect(ratio > 1.9)
        #expect(ratio < 2.1)
    }

    @Test func thumbnailOfAMissingPhotoIsNil() {
        let folder = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(VisitPhotoStore.thumbnail(filename: "no-such-photo.jpg", baseURL: folder) == nil)
    }

    @Test func downscaledToALimitKeepsAspectRatio() {
        let shrunk = VisitPhotoStore.downscaled(makeImage(width: 800, height: 400), toMaxDimension: 200)
        // Ranges, not exact sizes: the scale math is floating point.
        #expect(shrunk.size.width <= 200.01)
        #expect(shrunk.size.width >= 199)
        #expect(shrunk.size.height <= 100.01)
        #expect(shrunk.size.height >= 99)
    }

    @Test func downscaledSmallImageIsUnchanged() {
        let small = VisitPhotoStore.downscaled(makeImage(width: 100, height: 50), toMaxDimension: 200)
        #expect(small.size.width == 100)
        #expect(small.size.height == 50)
    }
}
