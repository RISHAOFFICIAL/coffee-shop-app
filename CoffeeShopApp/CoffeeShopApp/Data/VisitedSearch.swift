import Foundation

/// The Visited search filter state (Story S10, Screen 11). Chips narrow by
/// tag, neighborhood, person, and rating, and combine with the text query:
/// a result must match the query (when one is typed) and every active
/// filter group.
struct VisitedSearchFilters: Equatable {
    var tags: Set<String> = []
    var neighborhoods: Set<String> = []
    var companionIDs: Set<UUID> = []
    var ratings: Set<Int> = []

    var isActive: Bool {
        !tags.isEmpty || !neighborhoods.isEmpty || !companionIDs.isEmpty || !ratings.isEmpty
    }
}

/// One search result: the visit plus the designed Matched line that says
/// why it matched, shown directly under the result title (hi-fi Screen 11).
/// The line is nil when nothing was searched or filtered: a plain browse
/// result has no match to explain.
struct VisitedSearchResult: Identifiable {
    var visit: Visit
    var matchedLine: String?

    var id: UUID { visit.id }
}

/// The unified Visited search (Story S10). One box searches shop name,
/// neighborhood, companion name, ordered item, tag, and note together,
/// because she may remember any one of them and not the shop name. Pure
/// logic, so the search screen and the tests run the same code.
enum VisitedSearch {
    /// Searches visits by query and filters, newest first. Every result
    /// that came from a query or a filter carries its Matched line.
    static func search(
        visits: [Visit],
        companions: [Companion],
        query: String,
        filters: VisitedSearchFilters
    ) -> [VisitedSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        let namesByID = Dictionary(uniqueKeysWithValues: companions.map { ($0.id, $0.name) })

        var results: [VisitedSearchResult] = []
        for visit in visits {
            var reasons: [String] = []

            if !trimmedQuery.isEmpty {
                let queryReasons = queryMatchReasons(for: visit, query: trimmedQuery, namesByID: namesByID)
                guard !queryReasons.isEmpty else { continue }
                reasons.append(contentsOf: queryReasons)
            }

            if filters.isActive {
                guard let filterReasons = filterMatchReasons(for: visit, filters: filters, namesByID: namesByID) else {
                    continue
                }
                reasons.append(contentsOf: filterReasons)
            }

            let matchedLine = reasons.isEmpty
                ? nil
                : "Matched: " + deduplicated(reasons).joined(separator: ", ")
            results.append(VisitedSearchResult(visit: visit, matchedLine: matchedLine))
        }
        return results.sorted { $0.visit.checkedInAt > $1.visit.checkedInAt }
    }

    /// The reasons a visit matches the text query, in the designed order:
    /// order, companion, tag, neighborhood, shop name, note. A note match
    /// says only "note": the note text itself is never printed in the line.
    private static func queryMatchReasons(
        for visit: Visit,
        query: String,
        namesByID: [UUID: String]
    ) -> [String] {
        var reasons: [String] = []
        if let order = visit.orderText, order.lowercased().contains(query) {
            reasons.append(order)
        }
        for id in visit.companionIDs {
            if let name = namesByID[id], name.lowercased().contains(query) {
                reasons.append("with \(name)")
            }
        }
        for tag in visit.tags where tag.lowercased().contains(query) {
            reasons.append(tag)
        }
        if visit.neighborhood.lowercased().contains(query) {
            reasons.append(visit.neighborhood)
        }
        if visit.shopName.lowercased().contains(query) {
            reasons.append(visit.shopName)
        }
        if let note = visit.note, note.lowercased().contains(query) {
            reasons.append("note")
        }
        return reasons
    }

    /// Checks the visit against every active filter group. Returns nil
    /// when any group fails, otherwise the reasons the filters matched.
    /// A filter group matches when the visit carries at least one of the
    /// group's selected values.
    private static func filterMatchReasons(
        for visit: Visit,
        filters: VisitedSearchFilters,
        namesByID: [UUID: String]
    ) -> [String]? {
        var reasons: [String] = []
        if !filters.tags.isEmpty {
            let matched = visit.tags.filter { tag in
                filters.tags.contains { $0.lowercased() == tag.lowercased() }
            }
            guard !matched.isEmpty else { return nil }
            reasons.append(contentsOf: matched)
        }
        if !filters.neighborhoods.isEmpty {
            guard filters.neighborhoods.contains(visit.neighborhood) else { return nil }
            reasons.append(visit.neighborhood)
        }
        if !filters.companionIDs.isEmpty {
            let matchedIDs = visit.companionIDs.filter { filters.companionIDs.contains($0) }
            guard !matchedIDs.isEmpty else { return nil }
            for id in matchedIDs {
                if let name = namesByID[id] {
                    reasons.append("with \(name)")
                }
            }
        }
        if !filters.ratings.isEmpty {
            guard let rating = visit.rating, filters.ratings.contains(rating) else { return nil }
            reasons.append("rated \(rating)")
        }
        return reasons
    }

    private static func deduplicated(_ reasons: [String]) -> [String] {
        var seen: Set<String> = []
        var kept: [String] = []
        for reason in reasons {
            let key = reason.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            kept.append(reason)
        }
        return kept
    }

    // MARK: - Chip values, drawn from the user's own visits

    /// Every tag on any visit, alphabetical, for the tag chips.
    static func availableTags(in visits: [Visit]) -> [String] {
        Array(Set(visits.flatMap(\.tags))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Every neighborhood with a visit, alphabetical, for the chips.
    static func availableNeighborhoods(in visits: [Visit]) -> [String] {
        Array(Set(visits.map(\.neighborhood))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Companions who appear on at least one visit, alphabetical.
    static func availableCompanions(in visits: [Visit], companions: [Companion]) -> [Companion] {
        let usedIDs = Set(visits.flatMap(\.companionIDs))
        return companions
            .filter { usedIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Ratings present on visits, highest first, for the rating chips.
    static func availableRatings(in visits: [Visit]) -> [Int] {
        Array(Set(visits.compactMap(\.rating))).sorted(by: >)
    }
}
