import Foundation
import AuthenticationServices

/// Sign in with Apple and the Supabase session (Sprint 6, Story S14).
/// The app works fully signed out; signing in only adds backup. The
/// Apple credential and the Supabase tokens live in the Keychain and
/// nowhere else. The Supabase project does not exist yet (Sprint 0
/// account step), so until it does, sign in succeeds locally and backup
/// honestly reports not set up: the sign in is real, the backup waits
/// for the service.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    /// The name Apple shared on the first sign in, if any. Apple only
    /// sends it once, so it is kept in the Keychain.
    @Published private(set) var displayName: String?
    /// The email Apple shared on the first sign in, if any. This may be
    /// a private relay address; the app never emails it.
    @Published private(set) var email: String?

    private let authClient = SupabaseSyncClient()

    var appleUserID: String? {
        KeychainHelper.string(for: .appleUserID)
    }

    var supabaseUserID: String? {
        KeychainHelper.string(for: .supabaseUserID)
    }

    var isBackupConfigured: Bool {
        authClient.isConfigured
    }

    /// What a completed sign in means for backup.
    enum SignInResult {
        /// The Supabase session is live: sync can run.
        case backedUp
        /// Signed in with Apple, but the backup service is not set up
        /// yet. The log stays on this phone until it is.
        case localOnly
    }

    /// Completes a Sign in with Apple authorization: stores the Apple
    /// credential, exchanges the identity token for a Supabase session
    /// when the backend is configured, and reports whether backup is
    /// live. Throws when the identity token is missing or the exchange
    /// fails; in that case nothing is stored and the user stays signed
    /// out, so a half finished sign in is impossible.
    func completeSignIn(with credential: ASAuthorizationAppleIDCredential) async throws -> SignInResult {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.isEmpty else {
            throw SupabaseSyncError.missingIdentityToken
        }

        var session: SupabaseSession?
        if authClient.isConfigured {
            session = try await authClient.exchangeAppleToken(idToken)
        }

        KeychainHelper.save(credential.user, for: .appleUserID)
        if let fullName = credential.fullName,
           let formatted = PersonNameComponentsFormatter().string(from: fullName),
           !formatted.isEmpty {
            KeychainHelper.save(formatted, for: .appleDisplayName)
        }
        if let email = credential.email, !email.isEmpty {
            KeychainHelper.save(email, for: .appleEmail)
        }
        if let session {
            store(session: session)
        }
        displayName = KeychainHelper.string(for: .appleDisplayName)
        email = KeychainHelper.string(for: .appleEmail)
        isSignedIn = true
        return session == nil ? .localOnly : .backedUp
    }

    /// A valid Supabase access token, refreshing first when the stored
    /// one is expired or about to expire. Nil when there is no session
    /// or the refresh fails, in which case the caller signs in again.
    func validAccessToken() async -> String? {
        guard let expiryText = KeychainHelper.string(for: .supabaseTokenExpiry),
              let expiryInterval = TimeInterval(expiryText) else {
            return nil
        }
        if Date(timeIntervalSince1970: expiryInterval) > Date().addingTimeInterval(60),
           let token = KeychainHelper.string(for: .supabaseAccessToken) {
            return token
        }
        guard let refreshToken = KeychainHelper.string(for: .supabaseRefreshToken) else {
            return nil
        }
        guard let session = try? await authClient.refreshSession(refreshToken) else {
            return nil
        }
        store(session: session)
        return session.accessToken
    }

    /// Restores a saved session on launch: the Keychain says whether a
    /// sign in exists, and Apple says whether it is still valid. A
    /// revoked or transferred credential clears the local session and
    /// keeps the local log untouched, per Flow H step 5.
    func restoreSession() async {
        guard let userID = appleUserID else {
            isSignedIn = false
            return
        }
        displayName = KeychainHelper.string(for: .appleDisplayName)
        email = KeychainHelper.string(for: .appleEmail)
        let state = await credentialState(for: userID)
        switch state {
        case .authorized:
            isSignedIn = true
        case .revoked, .notFound, .transferred:
            clearLocalSession()
        @unknown default:
            isSignedIn = true
        }
    }

    /// Signs out: the Supabase session ends server side when one exists,
    /// and every session item leaves the Keychain. Local data is never
    /// touched here; SyncManager owns the local side of sign out.
    func signOut() async {
        if let token = KeychainHelper.string(for: .supabaseAccessToken) {
            await authClient.logout(accessToken: token)
        }
        clearLocalSession()
    }

    /// Clears the Keychain session and the published state. Local data
    /// is never touched.
    func clearLocalSession() {
        KeychainHelper.deleteAllSessionItems()
        displayName = nil
        email = nil
        isSignedIn = false
    }

    private func store(session: SupabaseSession) {
        KeychainHelper.save(session.accessToken, for: .supabaseAccessToken)
        KeychainHelper.save(session.refreshToken, for: .supabaseRefreshToken)
        KeychainHelper.save(session.user.id.uuidString, for: .supabaseUserID)
        let expiry = Date().addingTimeInterval(session.expiresIn).timeIntervalSince1970
        KeychainHelper.save(String(expiry), for: .supabaseTokenExpiry)
    }

    private func credentialState(for userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }
}
