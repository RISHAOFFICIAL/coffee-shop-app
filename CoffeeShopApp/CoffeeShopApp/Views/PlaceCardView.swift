import SwiftUI

/// The map pin preview card (Screen 2): name, neighborhood, hours, open or
/// closed, and independent or chain. Tapping it opens shop detail.
struct PlaceCardView: View {
    let shop: Shop
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shop.name)
                        .font(.coffeeCardTitle)
                        .foregroundStyle(.appText)
                        .lineLimit(1)
                    if shop.isSample {
                        SampleBadge()
                    }
                }
                Text("\(shop.neighborhood), \(shop.kind.displayText)")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                OpenStatusView(shop: shop)
                Text("Tap for hours, photos, directions")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.appTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
        .padding(CoffeeSpacing.screenMargin)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shop.name), \(shop.neighborhood), \(shop.kind.displayText), \(shop.openStatusText)")
        .accessibilityHint("Tap to open shop detail")
    }
}

/// A caramel map pin with a coffee cup, larger when selected.
struct ShopPinView: View {
    let shop: Shop
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appAccent)
                .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: isSelected ? 17 : 14))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("\(shop.name) pin")
    }
}

/// One row in the Discover list (Screen 3): name, neighborhood, hours,
/// open status, and distance when location is on.
struct ShopRowView: View {
    let shop: Shop
    var distanceText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shop.name)
                        .font(.coffeeCardTitle)
                        .foregroundStyle(.appText)
                        .lineLimit(1)
                    if shop.isSample {
                        SampleBadge()
                    }
                }
                Text("\(shop.neighborhood), \(shop.kind.displayText)")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                OpenStatusView(shop: shop)
            }
            Spacer()
            if let distanceText {
                Text(distanceText)
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appTextSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appTextSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    /// The row as VoiceOver reads it: name, neighborhood, kind, open
    /// status, and the distance when location is on.
    private var rowAccessibilityLabel: String {
        var label = "\(shop.name), \(shop.neighborhood), \(shop.kind.displayText), \(shop.openStatusText)"
        if let distanceText {
            label += ", \(distanceText) away"
        }
        return label
    }
}
