import SwiftUI

/// Liquid Glass treatments from the approved hi-fi spec, applied where the
/// design calls for them: the search bar on the map, place cards, the
/// check in prompt card, sheets, and primary buttons. The tab bar uses the
/// native iOS 26 glass tab bar. Contrast wins over style: text on glass
/// sits on a scrim strong enough to pass contrast.

extension View {
    /// A frosted glass card, 16pt radius, per the hi-fi spec.
    func glassCard() -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    /// A frosted glass pill, for the map search bar and floating controls.
    func glassPill() -> some View {
        glassEffect(.regular, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

/// The espresso primary button from the hi-fi spec: 17pt semibold white
/// text on espresso, 14pt radius, minimum 44pt tap target.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.coffeeButton)
            .foregroundStyle(.appPrimaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CoffeeSpacing.minTapTarget)
            .padding(.horizontal, CoffeeSpacing.screenMargin)
            .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A quiet secondary button: caramel text on the chip background.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.coffeeButton)
            .foregroundStyle(.appAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CoffeeSpacing.minTapTarget)
            .padding(.horizontal, CoffeeSpacing.screenMargin)
            .background(Color.appChipBackground, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A small rounded chip, used for tags, kind, and filter state.
struct ChipView: View {
    let text: String
    var isSelected: Bool = false

    var body: some View {
        Text(text)
            .font(.coffeeSecondary.weight(.semibold))
            .foregroundStyle(isSelected ? Color.appPrimaryText : Color.appChipText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.appAccent : Color.appChipBackground, in: Capsule())
    }
}

/// Open or closed status, always with the word spelled out, never color alone.
struct OpenStatusView: View {
    let shop: Shop

    var body: some View {
        Text(shop.openStatusText)
            .font(.coffeeSecondary.weight(.semibold))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        guard shop.weeklyHours.hasAnyHours else { return .appTextSecondary }
        if shop.isOpenNow == true { return .openGreen }
        return .closedRed
    }
}

/// The "Sample data" badge shown on every debug sample shop, so a sample
/// is never mistaken for a real shop.
struct SampleBadge: View {
    var body: some View {
        Text("Sample data")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.appPrimaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.appAccent, in: Capsule())
            .accessibilityLabel("Sample data, not a real shop")
    }
}

/// The quiet same day recovery card (Flow C step 7): a dismissed prompt
/// never repeats, but the user can still log it by hand today.
struct RecoveryCardView: View {
    let arrival: DismissedArrival
    let onLogIt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer")
                .foregroundStyle(.appAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Missed a check in at \(arrival.shopName)?")
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appText)
                Text("\(arrival.neighborhood), Detroit. Tap to log it.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            Spacer()
            Button("Log It", action: onLogIt)
                .font(.coffeeSecondary.weight(.semibold))
                .foregroundStyle(.appPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appPrimary, in: Capsule())
        }
        .padding(12)
        .background(Color.appSurfaceAlt, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
    }
}
