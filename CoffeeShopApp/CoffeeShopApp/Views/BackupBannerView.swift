import SwiftUI

/// The small signed out banner for Screens 9 and 13 (Flow H step 4).
/// It shows only when there are visits waiting for backup, and tapping
/// it opens Sign In. It never nags when there is nothing to protect.
struct BackupBannerView: View {
    var onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.appAccent)
                Text("Not backed up yet. Sign in to protect your list.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appText)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("Sign In")
                    .font(.coffeeSecondary)
                    .fontWeight(.semibold)
                    .foregroundStyle(.appPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.appSurfaceAlt, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Not backed up yet. Sign in to protect your list.")
    }
}

/// The backup reminder card for Screen 9 (Flow H step 1). It appears
/// only after the third check in, and only once: Not Now dismisses it
/// for good, so it never becomes a nag.
struct BackupReminderCardView: View {
    var visitCount: Int
    var onSignIn: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.appAccent)
                Text("Back up your log")
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appText)
            }
            Text("You have \(visitCount) visits saved on this phone. Sign in to back them up, so a new phone keeps them.")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
            HStack(spacing: 12) {
                Button("Sign In", action: onSignIn)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Not Now", action: onDismiss)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding()
        .background(.appSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.appLine, lineWidth: 1)
        )
    }
}
