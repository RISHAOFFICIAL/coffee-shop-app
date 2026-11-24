import Foundation
import Testing
@testable import CoffeeShopApp

/// The Supabase sync client (Sprint 6, Story S14) against a stubbed
/// URLSession: requests hit the right endpoints with the right headers,
/// responses decode, and a missing backend fails honestly instead of
/// hanging. No network call ever leaves the test process. Serialized:
/// every test shares the one static mock handler, so parallel runs
/// would answer each other's requests.
@Suite(.serialized)
struct SupabaseSyncClientTests {
    /// Intercepts every request and answers from the handler the test
    /// sets. The last request is kept for assertions.
    final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            do {
                guard let handler = Self.handler else {
                    throw URLError(.unknown)
                }
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private static func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SupabaseSyncClient {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return SupabaseSyncClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-anon-key"
        )
    }

    private static func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// The request body as text. The URL loading system hands a custom
    /// protocol the body as a stream, not as httpBody, so the mock reads
    /// the stream when httpBody is empty.
    private static func bodyString(of request: URLRequest) -> String {
        if let data = request.httpBody, !data.isEmpty {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func visitJSON(id: UUID, shopName: String) -> String {
        """
        {"id":"\(id.uuidString)","owner_id":"\(UUID().uuidString)","shop_id":"\(UUID().uuidString)","shop_name":"\(shopName)","neighborhood":"Midtown","address":"1 Test Street","checked_in_at":"2026-11-23T15:04:05.123+00:00","source":"manual","rating":5,"tags":["Cozy"],"order_text":"Latte","note":null,"companion_ids":[],"photo_path":null,"is_unverified_shop":false,"created_at":"2026-11-23T15:04:05.123+00:00","updated_at":"2026-11-23T15:04:05.123+00:00"}
        """
    }

    @Test func fetchVisitsDecodesDTOs() async throws {
        let id = UUID()
        let client = Self.makeClient { request in
            #expect(request.url?.path == "/rest/v1/visits")
            #expect(request.value(forHTTPHeaderField: "apikey") == "test-anon-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")
            return (Self.response(for: request), Data("[\(Self.visitJSON(id: id, shopName: "Test Coffee"))]".utf8))
        }
        let visits = try await client.fetchVisits(accessToken: "user-token")
        #expect(visits.count == 1)
        #expect(visits.first?.id == id)
        #expect(visits.first?.shopName == "Test Coffee")
        #expect(visits.first?.rating == 5)
    }

    @Test func upsertVisitsSendsMergeDuplicatesPreference() async throws {
        let visit = Visit(
            shopID: UUID(),
            shopName: "Test Coffee",
            neighborhood: "Midtown",
            address: "1 Test Street",
            checkedInAt: Date(),
            source: .manual
        )
        let client = Self.makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/rest/v1/visits")
            #expect(request.url?.query?.contains("on_conflict=id") == true)
            #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=minimal")
            return (Self.response(for: request, status: 201), Data())
        }
        try await client.upsertVisits([VisitDTO(from: visit, ownerID: UUID())], accessToken: "user-token")
    }

    @Test func upsertWithNoRowsMakesNoRequest() async throws {
        MockURLProtocol.lastRequest = nil
        let client = Self.makeClient { request in
            (Self.response(for: request), Data())
        }
        try await client.upsertVisits([], accessToken: "user-token")
        try await client.deleteVisits(ids: [], accessToken: "user-token")
        #expect(MockURLProtocol.lastRequest == nil)
    }

    @Test func exchangeAppleTokenPostsToTokenEndpoint() async throws {
        let userID = UUID()
        let client = Self.makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/auth/v1/token")
            #expect(request.url?.query?.contains("grant_type=id_token") == true)
            #expect(request.value(forHTTPHeaderField: "apikey") == "test-anon-key")
            let body = Self.bodyString(of: request)
            #expect(body.contains("apple"))
            #expect(body.contains("identity-token"))
            let sessionJSON = """
            {"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"\(userID.uuidString)"}}
            """
            return (Self.response(for: request), Data(sessionJSON.utf8))
        }
        let session = try await client.exchangeAppleToken("identity-token")
        #expect(session.accessToken == "new-access")
        #expect(session.refreshToken == "new-refresh")
        #expect(session.expiresIn == 3600)
        #expect(session.user.id == userID)
    }

    @Test func refreshSessionPostsRefreshGrant() async throws {
        let client = Self.makeClient { request in
            #expect(request.url?.query?.contains("grant_type=refresh_token") == true)
            let body = Self.bodyString(of: request)
            #expect(body.contains("old-refresh"))
            let sessionJSON = """
            {"access_token":"refreshed-access","refresh_token":"refreshed-refresh","expires_in":3600,"user":{"id":"\(UUID().uuidString)"}}
            """
            return (Self.response(for: request), Data(sessionJSON.utf8))
        }
        let session = try await client.refreshSession("old-refresh")
        #expect(session.accessToken == "refreshed-access")
    }

    @Test func unauthorizedResponseThrowsUnauthorized() async {
        let client = Self.makeClient { request in
            (Self.response(for: request, status: 401), Data())
        }
        await #expect(throws: SupabaseSyncError.unauthorized) {
            try await client.fetchVisits(accessToken: "expired-token")
        }
    }

    @Test func notConfiguredClientThrowsNotConfigured() async {
        let client = SupabaseSyncClient(session: .shared, baseURL: nil, anonKey: nil)
        #expect(client.isConfigured == false)
        await #expect(throws: SupabaseSyncError.notConfigured) {
            try await client.fetchVisits(accessToken: "user-token")
        }
    }

    @Test func photoPathIsNamespacedByOwnerAndVisit() {
        let ownerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let visitID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        #expect(SupabaseSyncClient.photoPath(ownerID: ownerID, visitID: visitID)
            == "11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.jpg")
    }
}
