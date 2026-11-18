import SwiftUI
import UIKit

/// Design system from the approved Stage 5 hi-fi spec (Oct 22, 2026).
/// Espresso and caramel on warm cream. Contrast was computed in the spec:
/// body text pairings are 6.7 to 1 or better against the 4.5 to 1 rule.
/// Every token has a light and a dark value from the same spec table.

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    /// A color with a light mode and a dark mode hex value.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // MARK: - Hi-fi tokens

    /// Warm cream page background. Light #FFF9F1, dark #17100B.
    static let appBackground = Color.dynamic(light: 0xFFF9F1, dark: 0x17100B)
    /// Card surface. Light #FFFFFF, dark #261A12.
    static let appSurface = Color.dynamic(light: 0xFFFFFF, dark: 0x261A12)
    /// Latte panel. Light #F7EBD9, dark #33241A.
    static let appSurfaceAlt = Color.dynamic(light: 0xF7EBD9, dark: 0x33241A)
    /// Primary text. Light #221409, dark #FFF6EC.
    static let appText = Color.dynamic(light: 0x221409, dark: 0xFFF6EC)
    /// Secondary text. Light #5C4232, dark #DEC7AC.
    static let appTextSecondary = Color.dynamic(light: 0x5C4232, dark: 0xDEC7AC)
    /// Espresso button in light mode, caramel light button in dark mode.
    static let appPrimary = Color.dynamic(light: 0x3A2113, dark: 0xE8AC67)
    /// Text on the primary button. Light #FFFFFF, dark #2A1708.
    static let appPrimaryText = Color.dynamic(light: 0xFFFFFF, dark: 0x2A1708)
    /// Caramel accent: pins, selected chips, tint. Light #8A4B12, dark #E8AC67.
    static let appAccent = Color.dynamic(light: 0x8A4B12, dark: 0xE8AC67)
    /// Chip background. Light #F1E2CC, dark #33241A.
    static let appChipBackground = Color.dynamic(light: 0xF1E2CC, dark: 0x33241A)
    /// Chip text. Light #3A2113, dark #FFF6EC.
    static let appChipText = Color.dynamic(light: 0x3A2113, dark: 0xFFF6EC)
    /// Hairlines. Light #D9C7AE, dark #4A3520.
    static let appLine = Color.dynamic(light: 0xD9C7AE, dark: 0x4A3520)
    /// Open Now green. Always paired with the word Open, never color alone.
    static let openGreen = Color.dynamic(light: 0x17603A, dark: 0x7ED0A0)
    /// Closed red. Always paired with the word Closed, never color alone.
    static let closedRed = Color.dynamic(light: 0x8A2F23, dark: 0xE08A7A)

    // MARK: - Scaffold aliases, kept so Sprint 0 views keep working

    static let espresso = Color.appPrimary
    static let caramel = Color.appAccent
    static let cream = Color.appBackground
    static let inkBrown = Color.appText
    static let softBrown = Color.appTextSecondary
}

/// Type scale from the hi-fi spec (SF Pro). Layouts are drawn at the
/// default size; primary actions must stay unclipped at the largest
/// accessibility size, stacking chips rather than shrinking text.
extension Font {
    /// Screen title, 28pt bold.
    static let coffeeTitle = Font.system(size: 28, weight: .bold)
    /// Card title, 17pt semibold.
    static let coffeeCardTitle = Font.system(size: 17, weight: .semibold)
    /// Body, 15pt.
    static let coffeeBody = Font.system(size: 15, weight: .regular)
    /// Secondary, 13pt.
    static let coffeeSecondary = Font.system(size: 13, weight: .regular)
    /// Button, 17pt semibold.
    static let coffeeButton = Font.system(size: 17, weight: .semibold)
    /// Tab label, 11pt semibold.
    static let coffeeTabLabel = Font.system(size: 11, weight: .semibold)
}

/// Spacing and radii from the hi-fi spec: 16pt screen margins, 8pt grid.
enum CoffeeSpacing {
    static let screenMargin: CGFloat = 16
    static let grid: CGFloat = 8
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    static let sheetRadius: CGFloat = 24
    static let minTapTarget: CGFloat = 44
}

/// One shared scaffold screen body: an honest statement of what this tab
/// will do and which sprint builds it. Tabs are replaced one by one as
/// their sprint lands; nothing here is a finished feature.
struct ScaffoldNoticeView: View {
    let title: String
    let message: String
    let sprint: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.appAccent)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.appText)
                    Text(message)
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Text(sprint)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.appText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .navigationTitle(title)
        }
    }
}
