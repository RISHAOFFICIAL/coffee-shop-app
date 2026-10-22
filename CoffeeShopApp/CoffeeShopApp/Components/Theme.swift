import SwiftUI

/// Design tokens from the approved Stage 5 hi-fi spec.
/// Espresso and caramel on warm cream. Contrast was computed in the spec:
/// body text pairings are 6.7 to 1 or better against the 4.5 to 1 rule.
/// Sprint 1 turns these tokens into the full design system, including the
/// native iOS 26 Liquid Glass treatments on the tab bar, cards, and sheets.
/// This scaffold deliberately uses only long-standing SwiftUI APIs so the
/// first Xcode Cloud build verifies the project, not exotic modifiers.
extension Color {
    static let espresso = Color(red: 0.227, green: 0.129, blue: 0.075)   // #3A2113
    static let caramel = Color(red: 0.541, green: 0.294, blue: 0.071)    // #8A4B12
    static let cream = Color(red: 1.000, green: 0.976, blue: 0.945)      // #FFF9F1
    static let inkBrown = Color(red: 0.133, green: 0.078, blue: 0.035)   // #221409
    static let softBrown = Color(red: 0.361, green: 0.259, blue: 0.196)  // #5C4232
    static let openGreen = Color(red: 0.090, green: 0.376, blue: 0.227)  // #17603A
}

/// One shared scaffold screen body: an honest statement of what this tab
/// will do and which sprint builds it. Sprint 1 replaces these one by one.
struct ScaffoldNoticeView: View {
    let title: String
    let message: String
    let sprint: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cream.ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.caramel)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.inkBrown)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Text(sprint)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.espresso)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .navigationTitle(title)
        }
    }
}
