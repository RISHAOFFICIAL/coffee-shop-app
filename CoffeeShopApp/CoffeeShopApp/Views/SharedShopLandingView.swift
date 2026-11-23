import SwiftUI
import SwiftData

/// Shared Shop Landing (Screen 14, Story S12): what a friend sees when
/// they tap a shared shop link and have the app. The shop, who shared it,
/// their rating and note when they included them, and one tap to Save To
/// Want To Go. Saving never adds the shop to Visited; only a check in
/// does that. The landing opens from the app link in the shared message;
/// a friend without the app gets the full details in the message text
/// instead, because no universal link domain was approved for version 1.
struct SharedShopLandingView: View {
    let payload: SharedShopPayload
    /// Called when the user picks View Want To Go after saving. The caller
    /// dismisses this landing and switches to the Want To Go tab.
    var onViewWantToGo: () -> Void = {}

    @Query private var shops: [Shop]
    @Query private var wantToGoEntries: [WantToGoEntry]
    @Query private var visits: [Visit]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The directory shop when this shared shop is in it, matched by id
    /// first, then by name and address. Nil for a shop outside the
    /// directory, which the landing still shows from the payload.
    private var directoryShop: Shop? {
        if let shopID = payload.shopID,
           let match = shops.first(where: { $0.id == shopID }) {
            return match
        }
        let nameKey = payload.name.lowercased()
        let addressKey = payload.address.lowercased()
        return shops.first {
            $0.name.lowercased() == nameKey && $0.address.lowercased() == addressKey
        }
    }

    private var isSaved: Bool {
        if let shopID = payload.shopID,
           wantToGoEntries.contains(where: { $0.shopID == shopID }) {
            return true
        }
        let nameKey = payload.name.lowercased()
        let addressKey = payload.address.lowercased()
        return wantToGoEntries.contains {
            $0.shopName.lowercased() == nameKey && $0.address.lowercased() == addressKey
        }
    }

    private var isVisited: Bool {
        if let shopID = payload.shopID,
           visits.contains(where: { $0.shopID == shopID }) {
            return true
        }
        let nameKey = payload.name.lowercased()
        let addressKey = payload.address.lowercased()
        return visits.contains {
            $0.shopName.lowercased() == nameKey && $0.address.lowercased() == addressKey
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CoffeeSpacing.screenMargin) {
                    header
                    if let rating = payload.rating {
                        ratingSection(rating: rating)
                    }
                    if let note = payload.note, !note.isEmpty {
                        noteSection(note: note)
                    }
                    actions
                    Text("Saving keeps this shop on your Want To Go list. It does not add it to Visited; only a check in does that.")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                }
                .padding(CoffeeSpacing.screenMargin)
            }
            .background(Color.appBackground)
            .navigationTitle("Shared With You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
            .navigationDestination(for: UUID.self) { shopID in
                if let shop = shops.first(where: { $0.id == shopID }) {
                    ShopDetailView(shop: shop)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sharedBy = payload.sharedBy {
                Text("Shared by \(sharedBy)")
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appAccent)
            } else {
                Text("Shared with you")
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appAccent)
            }
            Text(payload.name)
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
            if !payload.neighborhood.isEmpty {
                Text("\(payload.neighborhood), Detroit")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
            }
            if let shop = directoryShop {
                OpenStatusView(shop: shop)
            }
            if !payload.address.isEmpty {
                Text(payload.address)
                    .font(.coffeeBody)
                    .foregroundStyle(.appText)
            }
            if isVisited {
                Text("You have already visited this shop.")
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appAccent)
            }
        }
    }

    private func ratingSection(rating: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rating")
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(.appAccent)
                }
            }
            .accessibilityLabel("Rated \(rating) out of 5 stars")
        }
    }

    private func noteSection(note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(noteTitle)
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            Text(note)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
        }
        .padding(CoffeeSpacing.screenMargin)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
    }

    private var noteTitle: String {
        if let sharedBy = payload.sharedBy {
            return "\(sharedBy)'s note"
        }
        return "Note"
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            if isVisited {
                savedStateBanner(text: "Already in your Visited list")
            } else if isSaved {
                savedStateBanner(text: "Saved to Want To Go")
                Button("View Want To Go") {
                    dismiss()
                    onViewWantToGo()
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Save To Want To Go") {
                    WantToGoStore(context: modelContext).saveShared(payload)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            if let shop = directoryShop {
                NavigationLink(value: shop.id) {
                    Text("View Full Shop Detail")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// A saved state shown as text, not a button, because there is nothing
    /// left to tap: the shop is already where it belongs.
    private func savedStateBanner(text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .font(.coffeeButton)
            .foregroundStyle(.appAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CoffeeSpacing.minTapTarget)
            .padding(.horizontal, CoffeeSpacing.screenMargin)
            .background(Color.appChipBackground, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
    }
}
