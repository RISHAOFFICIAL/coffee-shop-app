import SwiftUI

/// The Filters sheet (Screen 4): Open Now, Independent Only, and a
/// neighborhood picker. Changes live in a draft until Apply, so the map
/// and list update together (Flow B step 5). Clear All is always visible.
struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss

    let neighborhoods: [String]
    let current: ShopFilterCriteria
    let onApply: (ShopFilterCriteria) -> Void

    @State private var draft: ShopFilterCriteria

    init(neighborhoods: [String], current: ShopFilterCriteria, onApply: @escaping (ShopFilterCriteria) -> Void) {
        self.neighborhoods = neighborhoods
        self.current = current
        self.onApply = onApply
        _draft = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $draft.openNowOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Now")
                                .font(.coffeeBody)
                            Text("Hide shops closed right now")
                                .font(.coffeeSecondary)
                                .foregroundStyle(.appTextSecondary)
                        }
                    }
                    Toggle(isOn: $draft.independentOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Independent Only")
                                .font(.coffeeBody)
                            Text("Hide chain locations")
                                .font(.coffeeSecondary)
                                .foregroundStyle(.appTextSecondary)
                        }
                    }
                }
                Section("Neighborhood") {
                    Picker("Neighborhood", selection: $draft.neighborhood) {
                        Text("All Detroit").tag(String?.none)
                        ForEach(neighborhoods, id: \.self) { neighborhood in
                            Text(neighborhood).tag(String?.some(neighborhood))
                        }
                    }
                }
                Section {
                    Button("Clear All") {
                        draft = ShopFilterCriteria(searchText: draft.searchText)
                    }
                    .foregroundStyle(.appAccent)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Filters") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
