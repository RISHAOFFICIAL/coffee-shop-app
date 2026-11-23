import Foundation
import Testing
@testable import CoffeeShopApp

/// The unified Visited search (Story S10): one box searches shop name,
/// neighborhood, companion, order, tag, and note, and every result
/// carries the designed Matched line. Pure logic, no store needed.
struct VisitedSearchTests {
    private let aricID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let mayaID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private func companions() -> [Companion] {
        [
            Companion(id: aricID, name: "Aric"),
            Companion(id: mayaID, name: "Maya"),
        ]
    }

    private func visits() -> [Visit] {
        [
            Visit(
                shopID: UUID(),
                shopName: "Sample Shop One",
                neighborhood: "Midtown",
                address: "1 Sample Street",
                checkedInAt: Date(timeIntervalSince1970: 1_790_000_000),
                source: .manual,
                rating: 5,
                tags: ["Quiet", "Good For Working"],
                orderText: "vanilla latte",
                note: "great light in the morning",
                companionIDs: [aricID]
            ),
            Visit(
                shopID: UUID(),
                shopName: "Sample Shop Two",
                neighborhood: "Corktown",
                address: "2 Sample Street",
                checkedInAt: Date(timeIntervalSince1970: 1_789_000_000),
                source: .manual,
                rating: 4,
                tags: ["Good Pastries"],
                orderText: "cold brew",
                companionIDs: [mayaID]
            ),
            Visit(
                shopID: UUID(),
                shopName: "Sample Shop Three",
                neighborhood: "Midtown",
                address: "3 Sample Street",
                checkedInAt: Date(timeIntervalSince1970: 1_788_000_000),
                source: .manual
            ),
        ]
    }

    @Test func queryFindsByOrderAndSaysWhy() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "latte",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 1)
        #expect(results.first?.visit.shopName == "Sample Shop One")
        #expect(results.first?.matchedLine == "Matched: vanilla latte")
    }

    @Test func queryFindsByCompanionAndSaysWhy() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "aric",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 1)
        #expect(results.first?.matchedLine == "Matched: with Aric")
    }

    @Test func queryFindsByNeighborhoodNewestFirst() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "midtown",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 2)
        #expect(results[0].visit.shopName == "Sample Shop One")
        #expect(results[1].visit.shopName == "Sample Shop Three")
        #expect(results[0].matchedLine == "Matched: Midtown")
    }

    @Test func queryFindsByTag() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "quiet",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 1)
        #expect(results.first?.matchedLine == "Matched: Quiet")
    }

    @Test func queryFindsByNoteWithoutPrintingTheNote() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "light",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 1)
        #expect(results.first?.matchedLine == "Matched: note")
        #expect(results.first?.matchedLine?.contains("great light") == false)
    }

    @Test func queryFindsByShopName() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "shop two",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 1)
        #expect(results.first?.visit.shopName == "Sample Shop Two")
    }

    @Test func queryWithNoMatchReturnsEmpty() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "matcha",
            filters: VisitedSearchFilters()
        )
        #expect(results.isEmpty)
    }

    @Test func tagFilterNarrowsToTaggedVisits() {
        var filters = VisitedSearchFilters()
        filters.tags = ["Good Pastries"]
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "",
            filters: filters
        )
        #expect(results.count == 1)
        #expect(results.first?.visit.shopName == "Sample Shop Two")
        #expect(results.first?.matchedLine == "Matched: Good Pastries")
    }

    @Test func ratingFilterNarrowsToThatRating() {
        var filters = VisitedSearchFilters()
        filters.ratings = [5]
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "",
            filters: filters
        )
        #expect(results.count == 1)
        #expect(results.first?.matchedLine == "Matched: rated 5")
    }

    @Test func personFilterNarrowsToThatCompanion() {
        var filters = VisitedSearchFilters()
        filters.companionIDs = [mayaID]
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "",
            filters: filters
        )
        #expect(results.count == 1)
        #expect(results.first?.visit.shopName == "Sample Shop Two")
    }

    @Test func queryAndFilterCombine() {
        var filters = VisitedSearchFilters()
        filters.tags = ["Quiet"]
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "midtown",
            filters: filters
        )
        #expect(results.count == 1)
        #expect(results.first?.visit.shopName == "Sample Shop One")
    }

    @Test func emptySearchReturnsAllNewestFirstWithNoMatchedLine() {
        let results = VisitedSearch.search(
            visits: visits(),
            companions: companions(),
            query: "",
            filters: VisitedSearchFilters()
        )
        #expect(results.count == 3)
        #expect(results[0].visit.shopName == "Sample Shop One")
        #expect(results[0].matchedLine == nil)
    }

    @Test func chipValuesComeFromTheVisits() {
        let all = visits()
        #expect(VisitedSearch.availableTags(in: all) == ["Good For Working", "Good Pastries", "Quiet"])
        #expect(VisitedSearch.availableNeighborhoods(in: all) == ["Corktown", "Midtown"])
        #expect(VisitedSearch.availableCompanions(in: all, companions: companions()).map(\.name) == ["Aric", "Maya"])
        #expect(VisitedSearch.availableRatings(in: all) == [5, 4])
    }
}
