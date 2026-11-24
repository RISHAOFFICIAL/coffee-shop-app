import Foundation

/// JSON encoding for the Supabase REST API: snake case keys, and ISO 8601
/// dates with fractional seconds, which is the format Supabase returns
/// for timestamptz columns. The plain `.iso8601` strategy cannot read
/// fractional seconds, so the formatter is built explicitly.
enum SupabaseJSON {
    static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeFormatter().string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = makeFormatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
            }
            return date
        }
        return decoder
    }
}

enum SupabaseSyncError: Error, Equatable {
    /// No Supabase project is configured yet (Sprint 0 account step).
    case notConfigured
    /// The session expired and could not be refreshed. Sign in again.
    case unauthorized
    case requestFailed(underlying: Error)
    case badResponse(status: Int)
    case decodingFailed(underlying: Error)
    /// Sign in with Apple returned no identity token.
    case missingIdentityToken

    /// Equality is by case, comparing the status code for a bad
    /// response. The underlying system errors are not compared: two
    /// failures of the same kind are the same failure for the caller,
    /// and Error itself has no equality.
    static func == (lhs: SupabaseSyncError, rhs: SupabaseSyncError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured),
             (.unauthorized, .unauthorized),
             (.missingIdentityToken, .missingIdentityToken),
             (.requestFailed, .requestFailed),
             (.decodingFailed, .decodingFailed):
            return true
        case (.badResponse(let lhsStatus), .badResponse(let rhsStatus)):
            return lhsStatus == rhsStatus
        default:
            return false
        }
    }
}

/// A Supabase auth session from the token endpoint: access and refresh
/// tokens, the expiry in seconds, and the user's id.
struct SupabaseSession: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: TimeInterval
    var user: SupabaseSessionUser

    struct SupabaseSessionUser: Decodable {
        var id: UUID
    }
}

// MARK: - Data transfer objects

/// One visit as it travels to and from the `visits` table. The local
/// Visit keeps its own fields; this struct is the wire shape only.
struct VisitDTO: Codable, Equatable {
    var id: UUID
    var ownerId: UUID
    var shopId: UUID
    var shopName: String
    var neighborhood: String
    var address: String
    var checkedInAt: Date
    var source: String
    var rating: Int?
    var tags: [String]
    var orderText: String?
    var note: String?
    var companionIds: [UUID]
    /// Storage path of the visit photo, for example
    /// "<user id>/<visit id>.jpg". Nil means the visit has no photo.
    var photoPath: String?
    var isUnverifiedShop: Bool
    var createdAt: Date
    var updatedAt: Date

    init(from visit: Visit, ownerID: UUID, photoPath: String? = nil) {
        self.id = visit.id
        self.ownerId = ownerID
        self.shopId = visit.shopID
        self.shopName = visit.shopName
        self.neighborhood = visit.neighborhood
        self.address = visit.address
        self.checkedInAt = visit.checkedInAt
        self.source = visit.sourceRaw
        self.rating = visit.rating
        self.tags = visit.tags
        self.orderText = visit.orderText
        self.note = visit.note
        self.companionIds = visit.companionIDs
        self.photoPath = photoPath
        self.isUnverifiedShop = visit.isUnverifiedShop
        self.createdAt = visit.createdAt
        self.updatedAt = visit.updatedAt
    }

    /// The local Visit for a downloaded row. Not inserted into any
    /// context; the caller inserts it. Starts synced: it came from the
    /// backup.
    func makeVisit() -> Visit {
        Visit(
            id: id,
            shopID: shopId,
            shopName: shopName,
            neighborhood: neighborhood,
            address: address,
            checkedInAt: checkedInAt,
            source: VisitSource(rawValue: source) ?? .manual,
            rating: rating,
            tags: tags,
            orderText: orderText,
            note: note,
            companionIDs: companionIds,
            photoFilename: photoPath == nil ? nil : VisitPhotoStore.filename(for: id),
            isUnverifiedShop: isUnverifiedShop,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStateRaw: SyncState.synced.rawValue
        )
    }

    /// How many joggers are filled in, the same count the merge rule
    /// uses to pick the winning version of a visit.
    var joggerCount: Int {
        var count = 0
        if rating != nil { count += 1 }
        if !tags.isEmpty { count += 1 }
        if orderText?.isEmpty == false { count += 1 }
        if note?.isEmpty == false { count += 1 }
        if !companionIds.isEmpty { count += 1 }
        if photoPath != nil { count += 1 }
        return count
    }
}

struct WantToGoDTO: Codable, Equatable {
    var id: UUID
    var ownerId: UUID
    var shopId: UUID
    var shopName: String
    var neighborhood: String
    var address: String
    var sharedBy: String?
    var noteFromSharer: String?
    var addedAt: Date
    var updatedAt: Date

    init(from entry: WantToGoEntry, ownerID: UUID) {
        self.id = entry.id
        self.ownerId = ownerID
        self.shopId = entry.shopID
        self.shopName = entry.shopName
        self.neighborhood = entry.neighborhood
        self.address = entry.address
        self.sharedBy = entry.sharedBy
        self.noteFromSharer = entry.noteFromSharer
        self.addedAt = entry.addedAt
        self.updatedAt = entry.updatedAt
    }

    func makeEntry() -> WantToGoEntry {
        WantToGoEntry(
            id: id,
            shopID: shopId,
            shopName: shopName,
            neighborhood: neighborhood,
            address: address,
            sharedBy: sharedBy,
            noteFromSharer: noteFromSharer,
            addedAt: addedAt,
            updatedAt: updatedAt,
            syncStateRaw: SyncState.synced.rawValue
        )
    }
}

struct CompanionDTO: Codable, Equatable {
    var id: UUID
    var ownerId: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(from companion: Companion, ownerID: UUID) {
        self.id = companion.id
        self.ownerId = ownerID
        self.name = companion.name
        self.createdAt = companion.createdAt
        self.updatedAt = companion.updatedAt
    }

    func makeCompanion() -> Companion {
        Companion(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// The synced slice of settings (Story S14). First launch state and the
/// last prompt line stay on the device: they describe this phone, not
/// the account.
struct UserSettingsDTO: Codable, Equatable {
    var userId: UUID
    var autoCheckInPromptsEnabled: Bool
    var shareNotesByDefault: Bool
    var sharerName: String?
    var updatedAt: Date

    init(from settings: UserSettings, userID: UUID) {
        self.userId = userID
        self.autoCheckInPromptsEnabled = settings.autoCheckInPromptsEnabled
        self.shareNotesByDefault = settings.shareNotesByDefault
        self.sharerName = settings.sharerName
        self.updatedAt = settings.updatedAt
    }
}

// MARK: - Client

/// The Supabase REST client for account sync (Sprint 6, Story S14).
/// Plain URLSession calls, the same approach as the directory client:
/// no third party SDK, no secret in source. The project URL and anon
/// key come from Info.plist (see supabase-config.md); until Risha
/// creates the Supabase project, every call reports notConfigured and
/// the app runs local only, which is the designed behavior, not an error.
/// User rows are scoped by row level security to their owner; the app
/// can only ever read and write the signed in user's own data.
struct SupabaseSyncClient {
    private let session: URLSession
    private let baseURL: URL?
    private let anonKey: String?

    init(
        session: URLSession = .shared,
        baseURL: URL? = SupabaseConfiguration.url,
        anonKey: String? = SupabaseConfiguration.anonKey
    ) {
        self.session = session
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    var isConfigured: Bool {
        baseURL != nil && anonKey != nil
    }

    // MARK: - Auth

    /// Exchanges a Sign in with Apple identity token for a Supabase
    /// session (GoTrue id_token grant). The Apple provider must be
    /// enabled in the Supabase dashboard; see supabase-config.md.
    func exchangeAppleToken(_ idToken: String) async throws -> SupabaseSession {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        guard let url = components?.url else { throw SupabaseSyncError.notConfigured }
        let body = try SupabaseJSON.encoder().encode(["provider": "apple", "id_token": idToken])
        let data = try await perform(url: url, method: "POST", body: body, bearerToken: anonKey, apiKey: anonKey)
        do {
            return try SupabaseJSON.decoder().decode(SupabaseSession.self, from: data)
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    /// Trades a refresh token for a fresh session.
    func refreshSession(_ refreshToken: String) async throws -> SupabaseSession {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw SupabaseSyncError.notConfigured }
        let body = try SupabaseJSON.encoder().encode(["refresh_token": refreshToken])
        let data = try await perform(url: url, method: "POST", body: body, bearerToken: anonKey, apiKey: anonKey)
        do {
            return try SupabaseJSON.decoder().decode(SupabaseSession.self, from: data)
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    /// Signs the session out server side. Best effort: a failure here
    /// never blocks the local sign out.
    func logout(accessToken: String) async {
        guard let baseURL, let anonKey else { return }
        let url = baseURL.appendingPathComponent("auth/v1/logout")
        _ = try? await perform(url: url, method: "POST", body: nil, bearerToken: accessToken, apiKey: anonKey)
    }

    // MARK: - Visits

    func fetchVisits(accessToken: String) async throws -> [VisitDTO] {
        let data = try await rest(
            path: "rest/v1/visits",
            method: "GET",
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "checked_in_at.desc"),
            ]
        )
        do {
            return try SupabaseJSON.decoder().decode([VisitDTO].self, from: data)
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    /// Upserts visits by id. A no-op for an empty list.
    func upsertVisits(_ visits: [VisitDTO], accessToken: String) async throws {
        guard !visits.isEmpty else { return }
        let body = try SupabaseJSON.encoder().encode(visits)
        _ = try await rest(
            path: "rest/v1/visits",
            method: "POST",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    /// Deletes visits by id. A no-op for an empty list.
    func deleteVisits(ids: [UUID], accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rest(
            path: "rest/v1/visits",
            method: "DELETE",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")],
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Want To Go

    func fetchWantToGo(accessToken: String) async throws -> [WantToGoDTO] {
        let data = try await rest(
            path: "rest/v1/want_to_go",
            method: "GET",
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "added_at.desc"),
            ]
        )
        do {
            return try SupabaseJSON.decoder().decode([WantToGoDTO].self, from: data)
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    func upsertWantToGo(_ entries: [WantToGoDTO], accessToken: String) async throws {
        guard !entries.isEmpty else { return }
        let body = try SupabaseJSON.encoder().encode(entries)
        _ = try await rest(
            path: "rest/v1/want_to_go",
            method: "POST",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    func deleteWantToGo(ids: [UUID], accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rest(
            path: "rest/v1/want_to_go",
            method: "DELETE",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")],
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Companions

    func fetchCompanions(accessToken: String) async throws -> [CompanionDTO] {
        let data = try await rest(
            path: "rest/v1/companions",
            method: "GET",
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "name.asc"),
            ]
        )
        do {
            return try SupabaseJSON.decoder().decode([CompanionDTO].self, from: data)
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    func upsertCompanions(_ companions: [CompanionDTO], accessToken: String) async throws {
        guard !companions.isEmpty else { return }
        let body = try SupabaseJSON.encoder().encode(companions)
        _ = try await rest(
            path: "rest/v1/companions",
            method: "POST",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    /// Deletes companions by id. Used by account deletion only; a
    /// companion is never deleted on its own in version 1.
    func deleteCompanions(ids: [UUID], accessToken: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rest(
            path: "rest/v1/companions",
            method: "DELETE",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")],
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Settings

    /// The synced settings row, or nil when this account has never
    /// backed up settings.
    func fetchSettings(userID: UUID, accessToken: String) async throws -> UserSettingsDTO? {
        let data = try await rest(
            path: "rest/v1/user_settings",
            method: "GET",
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            ]
        )
        do {
            return try SupabaseJSON.decoder().decode([UserSettingsDTO].self, from: data).first
        } catch {
            throw SupabaseSyncError.decodingFailed(underlying: error)
        }
    }

    func upsertSettings(_ settings: UserSettingsDTO, accessToken: String) async throws {
        let body = try SupabaseJSON.encoder().encode(settings)
        _ = try await rest(
            path: "rest/v1/user_settings",
            method: "POST",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id")],
            body: body,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    func deleteSettings(userID: UUID, accessToken: String) async throws {
        _ = try await rest(
            path: "rest/v1/user_settings",
            method: "DELETE",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")],
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    // MARK: - Visit photos (Supabase Storage)

    /// The storage path for a visit photo: one folder per user, one file
    /// per visit. Row level security on the bucket allows only the owner.
    static func photoPath(ownerID: UUID, visitID: UUID) -> String {
        "\(ownerID.uuidString)/\(visitID.uuidString).jpg"
    }

    func uploadPhoto(_ data: Data, path: String, accessToken: String) async throws {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        let url = baseURL.appendingPathComponent("storage/v1/object/visit-photos/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        _ = try await perform(request)
    }

    func downloadPhoto(path: String, accessToken: String) async throws -> Data {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        let url = baseURL.appendingPathComponent("storage/v1/object/visit-photos/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func deletePhotos(paths: [String], accessToken: String) async throws {
        guard !paths.isEmpty else { return }
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        let url = baseURL.appendingPathComponent("storage/v1/object/visit-photos")
        let body = try SupabaseJSON.encoder().encode(["prefixes": paths])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await perform(request)
    }

    // MARK: - Account deletion

    /// Calls the delete-account edge function, which removes the auth
    /// user (and, by cascade, every user row) with the service role key.
    /// The app never holds the service role key, so this call is the
    /// only way the auth record itself is deleted. The function must be
    /// deployed; see supabase-config.md.
    func deleteAccount(accessToken: String) async throws {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        let url = baseURL.appendingPathComponent("functions/v1/delete-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try SupabaseJSON.encoder().encode([String: String]())
        _ = try await perform(request)
    }

    // MARK: - Request plumbing

    private func rest(
        path: String,
        method: String,
        accessToken: String,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let baseURL, let anonKey else { throw SupabaseSyncError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw SupabaseSyncError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        return try await perform(request)
    }

    private func perform(
        url: URL,
        method: String,
        body: Data?,
        bearerToken: String,
        apiKey: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SupabaseSyncError.requestFailed(underlying: error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseSyncError.badResponse(status: 0)
        }
        if httpResponse.statusCode == 401 {
            throw SupabaseSyncError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseSyncError.badResponse(status: httpResponse.statusCode)
        }
        return data
    }
}
