import SwiftUI
import AuthenticationServices

/// Screen 15: Sign In (Sprint 6, Story S14). One purpose, said plainly:
/// back up the Visited and Want To Go lists so a new phone keeps them.
/// Signing in is optional everywhere it appears; the sheet always
/// offers to continue without it. A cancelled sign in is silent; any
/// other failure gets one plain line and a chance to try again.
struct SignInView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    /// Called on Done after a successful sign in, so the caller can
    /// finish its own flow (first launch completes after sign in).
    var onDoneAfterSignIn: (() -> Void)?

    @State private var isSigningIn = false
    @State private var confirmation: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Back up your log")
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                Text("Back up your Visited and Want To Go lists so a new phone keeps them.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                Text("Sign in with Apple. Your name and email stay private, and nothing about your visits is ever shared.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)

                if let confirmation {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.openGreen)
                        Text(confirmation)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                    }
                    .padding()
                    .background(.appSurfaceAlt, in: RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.coffeeBody)
                        .foregroundStyle(.closedRed)
                }

                if confirmation == nil {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .disabled(isSigningIn)
                    .opacity(isSigningIn ? 0.6 : 1)
                    .accessibilityLabel("Sign in with Apple")

                    if isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Signing in")
                                .font(.coffeeSecondary)
                                .foregroundStyle(.appTextSecondary)
                        }
                    }

                    if !syncManager.isSignedIn && !isBackupConfigured {
                        Text("Backup is not set up yet. Your log stays on this phone until it is, and signing in now keeps your account ready for when it is.")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                }

                Spacer()

                if confirmation != nil {
                    Button("Done") {
                        dismiss()
                        onDoneAfterSignIn?()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Continue Without Signing In") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
            .background(.appBackground)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var isBackupConfigured: Bool {
        SupabaseConfiguration.isConfigured
    }

    private func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Sign in did not work. Please try again."
                return
            }
            isSigningIn = true
            errorMessage = nil
            Task {
                do {
                    let message = try await syncManager.signIn(with: credential)
                    confirmation = message
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSigningIn = false
            }
        case .failure(let error):
            // A cancelled sign in is a choice, not an error: silent.
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = "Sign in did not work. Please try again."
        }
    }
}
