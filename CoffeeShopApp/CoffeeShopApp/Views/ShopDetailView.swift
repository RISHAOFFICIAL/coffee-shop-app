import SwiftUI
import SwiftData

/// Shop detail (Screen 5): name, address, neighborhood, weekly hours,
/// independent or chain, tags, a cleared photo where one exists, and the
/// main actions: Directions, Check In Here, and Save to Want To Go. The
/// verification line shows where the data came from and when it was last
/// checked, so the directory never pretends to be fresher than it is.
struct ShopDetailView: View {
    let shop: Shop

    @Query private var wantToGoEntries: [WantToGoEntry]
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.modelContext) private var modelContext

    /// True when this shop is already on the Want To Go list.
    private var isSavedToWantToGo: Bool {
        wantToGoEntries.contains { $0.shopID == shop.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CoffeeSpacing.screenMargin) {
                photoArea
                header
                actions
                hoursSection
                if !shop.tags.isEmpty {
                    tagsSection
                }
                verificationLine
            }
            .padding(CoffeeSpacing.screenMargin)
        }
        .background(Color.appBackground)
        .navigationTitle("Shop Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoArea: some View {
        if let photoURLString = shop.photoURL,
           let photoURL = URL(string: photoURLString),
           shop.photoRights != nil {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            Color.appSurfaceAlt
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.appAccent)
                Text("Photo coming soon")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
    }

    // MARK: - Header and actions

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(shop.name)
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                if shop.isSample {
                    SampleBadge()
                }
            }
            Text("\(shop.kind.displayText), \(shop.neighborhood), Detroit")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
            OpenStatusView(shop: shop)
            Text(shop.address)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            if let distanceText = shop.distanceText(from: locationService.lastLocation) {
                Text(distanceText + " away")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            if shop.isUserEntered {
                Text("Added by you, not verified directory data.")
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appAccent)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button("Directions", action: openDirections)
                .buttonStyle(PrimaryButtonStyle())
            Button("Check In Here") {
                checkInManager.manualCheckIn(shop: shop)
            }
            .buttonStyle(SecondaryButtonStyle())
            Button(isSavedToWantToGo ? "Saved to Want To Go" : "Save to Want To Go") {
                toggleWantToGo()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Saves the shop to Want To Go, or removes it when it is already
    /// saved. Saving never creates a visit; only a check in does.
    private func toggleWantToGo() {
        let store = WantToGoStore(context: modelContext)
        if let entry = store.entry(forShopID: shop.id) {
            store.remove(entry)
        } else {
            store.save(shop: shop)
        }
    }

    // MARK: - Hours, tags, verification

    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hours this week")
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            if shop.weeklyHours.hasAnyHours {
                ForEach(shop.weeklyHours.summaryLines(), id: \.day) { line in
                    HStack {
                        Text(line.day)
                            .font(.coffeeBody)
                            .foregroundStyle(.appTextSecondary)
                            .frame(width: 40, alignment: .leading)
                        Text(line.text)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                        Spacer()
                    }
                }
            } else {
                Text("Hours not verified yet for this shop.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
            }
        }
        .padding(CoffeeSpacing.screenMargin)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            FlowLayout(spacing: 8) {
                ForEach(shop.tags, id: \.self) { tag in
                    ChipView(text: tag)
                }
            }
        }
    }

    private var verificationLine: some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return Text("Source: \(shop.source). Last verified \(formatter.string(from: shop.lastVerifiedDate)).")
            .font(.coffeeSecondary)
            .foregroundStyle(.appTextSecondary)
    }

    // MARK: - Directions

    private func openDirections() {
        Directions.open(coordinate: shop.coordinate, name: shop.name)
    }
}

/// A simple wrapping row layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, point) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? 0
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
