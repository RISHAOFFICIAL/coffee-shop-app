import SwiftUI
import SwiftData

/// Visited Search (Screen 11, Story S10): find a shop even when the name
/// is exactly what was forgotten. One box searches shop name, neighborhood,
/// companion, order, tag, and note together; chips below narrow by tag,
/// neighborhood, person, and rating. Every result carries the designed
/// Matched line directly under its title, so she can tell instantly if it
/// is the right shop. A search with no results is never a dead end: it
/// offers clearing the filters, browsing all Visited, and checking
/// Want To Go, because a shop she only meant to visit can feel like a
/// memory too (Flow E).
struct VisitedSearchView: View {
    /// Called when the user picks Check Want To Go from the empty results
    /// screen. The caller switches to the Want To Go tab.
    var onCheckWantToGo: () -> Void = {}

    @Query(sort: \Visit.checkedInAt, order: .reverse) private var visits: [Visit]
    @Query private var companions: [Companion]
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var filters = VisitedSearchFilters()

    private var results: [VisitedSearchResult] {
        VisitedSearch.search(
            visits: visits,
            companions: companions,
            query: searchText,
            filters: filters
        )
    }

    private var availableTags: [String] {
        VisitedSearch.availableTags(in: visits)
    }

    private var availableNeighborhoods: [String] {
        VisitedSearch.availableNeighborhoods(in: visits)
    }

    private var availableCompanions: [Companion] {
        VisitedSearch.availableCompanions(in: visits, companions: companions)
    }

    private var availableRatings: [Int] {
        VisitedSearch.availableRatings(in: visits)
    }

    var body: some View {
        Group {
            if visits.isEmpty {
                noVisitsYet
            } else if results.isEmpty {
                noResults
            } else {
                resultsList
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Search Visited")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Results

    private var resultsList: some View {
        List {
            Section {
                searchField
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                Text("One box searches name, neighborhood, person, order, tag, and note.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                filterChips
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }
            ForEach(results) { result in
                NavigationLink(value: result.visit.id) {
                    VisitRowView(
                        visit: result.visit,
                        companionNames: companionNames(for: result.visit),
                        matchedLine: result.matchedLine
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.appTextSecondary)
            TextField("Search Visited", text: $searchText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: CoffeeSpacing.minTapTarget)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
    }

    // MARK: - Filter chips

    @ViewBuilder
    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !availableTags.isEmpty {
                chipGroup(title: "Tag") {
                    ForEach(availableTags, id: \.self) { tag in
                        chipButton(
                            label: tag,
                            isSelected: filters.tags.contains(tag)
                        ) {
                            toggle(&filters.tags, value: tag)
                        }
                    }
                }
            }
            if !availableNeighborhoods.isEmpty {
                chipGroup(title: "Neighborhood") {
                    ForEach(availableNeighborhoods, id: \.self) { neighborhood in
                        chipButton(
                            label: neighborhood,
                            isSelected: filters.neighborhoods.contains(neighborhood)
                        ) {
                            toggle(&filters.neighborhoods, value: neighborhood)
                        }
                    }
                }
            }
            if !availableCompanions.isEmpty {
                chipGroup(title: "Person") {
                    ForEach(availableCompanions) { companion in
                        chipButton(
                            label: companion.name,
                            isSelected: filters.companionIDs.contains(companion.id)
                        ) {
                            toggle(&filters.companionIDs, value: companion.id)
                        }
                    }
                }
            }
            if !availableRatings.isEmpty {
                chipGroup(title: "Rating") {
                    ForEach(availableRatings, id: \.self) { rating in
                        chipButton(
                            label: "\(rating) stars",
                            isSelected: filters.ratings.contains(rating)
                        ) {
                            toggle(&filters.ratings, value: rating)
                        }
                    }
                }
            }
        }
    }

    private func chipGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.coffeeSecondary.weight(.semibold))
                .foregroundStyle(.appTextSecondary)
            FlowLayout(spacing: 8) {
                content()
            }
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChipView(text: label, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter\(isSelected ? ", selected" : "")")
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, value: T) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    // MARK: - Empty states

    private var noVisitsYet: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.appAccent)
            Text("No visits to search yet.")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
            Button("Browse All Visited") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchField
                Text("One box searches name, neighborhood, person, order, tag, and note.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                filterChips
                VStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.appAccent)
                        .padding(.top, 24)
                    Text("No visits match that.")
                        .font(.coffeeCardTitle)
                        .foregroundStyle(.appText)
                    Text("Try a different word, or clear the filters and browse everything you have visited.")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                        .multilineTextAlignment(.center)
                    Button("Clear Filters") {
                        searchText = ""
                        filters = VisitedSearchFilters()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Browse All Visited") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Check Want To Go") {
                        dismiss()
                        onCheckWantToGo()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(CoffeeSpacing.screenMargin)
        }
    }

    private func companionNames(for visit: Visit) -> [String] {
        visit.companionIDs.compactMap { id in
            companions.first(where: { $0.id == id })?.name
        }
    }
}
