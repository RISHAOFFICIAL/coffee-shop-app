import SwiftUI

/// First launch (Screen 1, Flow A): what the app does, how auto check in
/// works in plain language before any system prompt, and the account offer.
/// No step requires an account, a payment, or typing. Skipping permissions
/// never blocks browsing the directory; every skipped step is reachable
/// later in Settings.
struct FirstLaunchView: View {
    var onComplete: () -> Void

    @EnvironmentObject private var locationService: LocationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Page {
        case intro
        case autoCheckIn
        case alwaysAccess
        case backup
    }

    @State private var page: Page = .intro
    @State private var showSignIn = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                switch page {
                case .intro: introPage
                case .autoCheckIn: autoCheckInPage
                case .alwaysAccess: alwaysAccessPage
                case .backup: backupPage
                }
                Spacer()
            }
            .padding(CoffeeSpacing.screenMargin)
            // The page slide is skipped with Reduce Motion on: the next
            // page just appears. This is the app's only animation.
            .animation(reduceMotion ? nil : .easeInOut, value: page)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onDoneAfterSignIn: onComplete)
        }
    }

    // MARK: - Pages

    private var introPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 64))
                .foregroundStyle(.appAccent)
            Text("Cupmarks")
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
            VStack(alignment: .leading, spacing: 12) {
                launchLine(icon: "map.fill", text: "Find every Detroit coffee shop, on a map and in a list.")
                launchLine(icon: "bookmark.fill", text: "Never forget the ones you visited. One tap saves each visit.")
            }
            Button("Continue") {
                page = .autoCheckIn
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var autoCheckInPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.fill")
                .font(.system(size: 52))
                .foregroundStyle(.appAccent)
            Text("Automatic check in")
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
            Text("When you arrive at a shop and stay a little while, we ask once: Were you at this shop? One tap saves it. Walking past a shop never prompts you.")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Turn On Auto Check In") {
                locationService.requestWhenInUseAuthorization()
                Task {
                    _ = await NotificationService.shared.requestAuthorization()
                }
                page = .alwaysAccess
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Not Now") {
                page = .backup
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("You can turn this on later in Settings. Browsing shops always works without it.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private var alwaysAccessPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.fill")
                .font(.system(size: 52))
                .foregroundStyle(.appAccent)
            Text("Prompts while the app is closed")
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
                .multilineTextAlignment(.center)
            Text("Always access is what lets prompts appear when the app is closed. With Only While Using The App, prompts only work while the app is open. Either way, your location never leaves this phone for prompts.")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Keep Always") {
                locationService.requestAlwaysAuthorization()
                page = .backup
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Only While Using The App") {
                page = .backup
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var backupPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 52))
                .foregroundStyle(.appAccent)
            Text("Your log lives on this phone")
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
                .multilineTextAlignment(.center)
            Text("Every check in saves on this phone first, even with no signal. Sign in to back up your log, so a new phone keeps it. Without an account, your log lives only on this phone.")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Sign In for Backup") {
                showSignIn = true
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Continue Without An Account") {
                onComplete()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func launchLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.appAccent)
                .frame(width: 24)
            Text(text)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
        }
    }
}
