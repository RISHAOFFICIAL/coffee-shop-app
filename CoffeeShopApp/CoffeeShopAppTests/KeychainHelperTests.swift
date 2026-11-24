import Foundation
import Testing
@testable import CoffeeShopApp

/// Keychain storage for the sign in session (Sprint 6, Story S14): the
/// Apple user id, the display name and email Apple shared once, and the
/// Supabase tokens. Values round trip, deletes remove them, and clearing
/// the session leaves nothing behind. Tests clean up after themselves,
/// so no test value survives in the Keychain. Serialized: every test
/// shares the one device Keychain, so parallel runs would read each
/// other's values.
@Suite(.serialized)
struct KeychainHelperTests {
    @Test func saveLoadAndDeleteRoundTrip() {
        KeychainHelper.save("test-user-123", for: .appleUserID)
        #expect(KeychainHelper.string(for: .appleUserID) == "test-user-123")
        KeychainHelper.delete(for: .appleUserID)
        #expect(KeychainHelper.string(for: .appleUserID) == nil)
    }

    @Test func missingKeyReadsNil() {
        KeychainHelper.delete(for: .appleDisplayName)
        #expect(KeychainHelper.string(for: .appleDisplayName) == nil)
    }

    @Test func saveOverwritesExistingValue() {
        KeychainHelper.save("first@example.com", for: .appleEmail)
        KeychainHelper.save("second@example.com", for: .appleEmail)
        #expect(KeychainHelper.string(for: .appleEmail) == "second@example.com")
        KeychainHelper.delete(for: .appleEmail)
    }

    @Test func deleteAllSessionItemsClearsEveryKey() {
        KeychainHelper.save("user", for: .appleUserID)
        KeychainHelper.save("Risha", for: .appleDisplayName)
        KeychainHelper.save("a@b.com", for: .appleEmail)
        KeychainHelper.save("access", for: .supabaseAccessToken)
        KeychainHelper.save("refresh", for: .supabaseRefreshToken)
        KeychainHelper.save("supabase-user", for: .supabaseUserID)
        KeychainHelper.save("1234567890", for: .supabaseTokenExpiry)
        KeychainHelper.deleteAllSessionItems()
        #expect(KeychainHelper.string(for: .appleUserID) == nil)
        #expect(KeychainHelper.string(for: .appleDisplayName) == nil)
        #expect(KeychainHelper.string(for: .appleEmail) == nil)
        #expect(KeychainHelper.string(for: .supabaseAccessToken) == nil)
        #expect(KeychainHelper.string(for: .supabaseRefreshToken) == nil)
        #expect(KeychainHelper.string(for: .supabaseUserID) == nil)
        #expect(KeychainHelper.string(for: .supabaseTokenExpiry) == nil)
    }
}
