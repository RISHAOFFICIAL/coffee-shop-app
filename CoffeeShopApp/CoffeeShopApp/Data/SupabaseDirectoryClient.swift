import Foundation

/// Supabase configuration for the directory refresh. The values come from
/// Info.plist keys (`SupabaseURL` and `SupabaseAnonKey`), which are set
/// from build settings after Risha creates the Supabase project (Sprint 0
/// account holder step). Until then both are empty and the client reports
/// not configured, so the app runs on its bundled verified directory.
/// No secret is ever written into source code.
enum SupabaseConfiguration {
    static var url: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var anonKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !raw.isEmpty else { return nil }
        return raw
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}

enum SupabaseDirectoryError: Error {
    case notConfigured
    case requestFailed(underlying: Error)
    case badResponse(status: Int)
    case decodingFailed(underlying: Error)
}

/// Reads the published Detroit directory from Supabase. The app only ever
/// reads: directory writes happen through the curation process with the
/// service role, never from the app (see supabase/schema.sql).
struct SupabaseDirectoryClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPublishedShops() async throws -> [ShopDTO] {
        guard let baseURL = SupabaseConfiguration.url,
              let anonKey = SupabaseConfiguration.anonKey else {
            throw SupabaseDirectoryError.notConfigured
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/shops"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "is_published", value: "eq.true"),
            URLQueryItem(name: "select", value: "id,name,address,neighborhood,latitude,longitude,kind,hours,tags,photo_url,photo_rights,source,last_verified_date,is_published"),
            URLQueryItem(name: "order", value: "name.asc"),
        ]
        guard let url = components?.url else {
            throw SupabaseDirectoryError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SupabaseDirectoryError.requestFailed(underlying: error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseDirectoryError.badResponse(status: 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseDirectoryError.badResponse(status: httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode([ShopDTO].self, from: data)
        } catch {
            throw SupabaseDirectoryError.decodingFailed(underlying: error)
        }
    }
}
