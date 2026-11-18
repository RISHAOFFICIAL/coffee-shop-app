import Foundation
import SwiftData

/// What Discover can say about the directory right now. The offline state
/// is explicit: cached shops show with their age, never silently stale.
enum DirectoryState: Equatable {
    case loading
    case loaded(shopCount: Int, lastUpdated: Date)
    case offlineCached(shopCount: Int, lastUpdated: Date)
    case empty
    case error(message: String)

    var shopCount: Int {
        switch self {
        case .loaded(let count, _), .offlineCached(let count, _): return count
        default: return 0
        }
    }
}

/// Owns the Detroit directory pipeline: the bundled verified batch seeds the
/// on device cache, and a Supabase refresh replaces it when the project is
/// configured. Local reads always win; the network never blocks the UI.
/// Views read shops through `@Query`; this store only manages loading,
/// refresh, and the directory state line.
@MainActor
final class DirectoryStore: ObservableObject {
    @Published private(set) var state: DirectoryState = .loading
    /// The batch date of the bundled file, shown honestly in Discover.
    @Published private(set) var bundledBatchDate: Date?

    private let context: ModelContext
    private let client: SupabaseDirectoryClient
    private let lastUpdatedKey = "CoffeeShopApp.DirectoryLastUpdated"

    init(context: ModelContext, client: SupabaseDirectoryClient = SupabaseDirectoryClient()) {
        self.context = context
        self.client = client
    }

    /// Seeds the cache from the bundled verified batch when it is empty,
    /// then attempts a network refresh when Supabase is configured.
    func load() async {
        state = .loading
        let cachedCount = (try? context.fetchCount(FetchDescriptor<Shop>())) ?? 0
        if cachedCount == 0 {
            await seedFromBundle()
        }
        await refresh()
    }

    /// Retries a failed refresh from the error or offline state.
    func retry() async {
        await refresh()
    }

    // MARK: - Bundled batch

    private func seedFromBundle() async {
        guard let url = Bundle.main.url(forResource: "detroit-shops-batch-1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let batch = try? JSONDecoder().decode(ShopBatchFile.self, from: data) else {
            #if DEBUG
            // Debug only fallback so the UI stays testable without data.
            // Sample shops are labeled in the UI and compiled out of
            // release builds; see SampleData.swift.
            for shop in SampleData.makeShops() {
                context.insert(shop)
            }
            try? context.save()
            #endif
            return
        }
        bundledBatchDate = ShopDTO.dateFormatter.date(from: batch.generated)
        var skipped = 0
        for dto in batch.shops {
            guard let shop = dto.toShop() else {
                skipped += 1
                continue
            }
            context.insert(shop)
        }
        try? context.save()
        if skipped > 0 {
            print("Directory seed skipped \(skipped) unusable rows.")
        }
        UserDefaults.standard.set(Date(), forKey: lastUpdatedKey)
    }

    // MARK: - Network refresh

    private func refresh() async {
        let cachedCount = (try? context.fetchCount(FetchDescriptor<Shop>())) ?? 0
        let lastUpdated = UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date ?? Date()
        guard SupabaseConfiguration.isConfigured else {
            // No Supabase project yet (Sprint 0 account holder step). The
            // bundled verified batch is the directory until then.
            if cachedCount == 0 {
                state = .empty
            } else {
                state = .loaded(shopCount: cachedCount, lastUpdated: lastUpdated)
            }
            return
        }
        do {
            let remote = try await client.fetchPublishedShops()
            upsert(remote)
            retireMissing(from: remote)
            try? context.save()
            UserDefaults.standard.set(Date(), forKey: lastUpdatedKey)
            let count = ((try? context.fetch(FetchDescriptor<Shop>())) ?? []).filter { $0.isPublished }.count
            state = .loaded(shopCount: count, lastUpdated: Date())
        } catch {
            if cachedCount > 0 {
                state = .offlineCached(shopCount: cachedCount, lastUpdated: lastUpdated)
            } else {
                state = .error(message: "The directory could not load. Check your connection and try again.")
            }
        }
    }

    /// Marks cached directory shops unpublished when the remote published
    /// list no longer includes them (a shop closed or was unpublished in
    /// Supabase). The row stays on the phone so existing visits keep their
    /// shop, but the shop stops appearing in Discover, manual check-in, and
    /// region monitoring. User entered shops and sample shops are never
    /// retired by the remote directory.
    private func retireMissing(from dtos: [ShopDTO]) {
        let publishedIDs = Set(dtos.map { $0.id })
        let existing = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
        for shop in existing where !publishedIDs.contains(shop.id) {
            if shop.isUserEntered || shop.isSample { continue }
            shop.isPublished = false
            shop.updatedAt = Date()
        }
    }

    /// Inserts new directory rows and updates changed ones, matched by the
    /// stable Supabase UUID. User entered shops and sample shops are never
    /// overwritten by the remote directory.
    private func upsert(_ dtos: [ShopDTO]) {
        let existing = (try? context.fetch(FetchDescriptor<Shop>())) ?? []
        var byID: [UUID: Shop] = [:]
        for shop in existing {
            byID[shop.id] = shop
        }
        for dto in dtos {
            guard let incoming = dto.toShop() else { continue }
            if let current = byID[dto.id] {
                if current.isUserEntered || current.isSample { continue }
                current.name = incoming.name
                current.address = incoming.address
                current.neighborhood = incoming.neighborhood
                current.latitude = incoming.latitude
                current.longitude = incoming.longitude
                current.kindRaw = incoming.kindRaw
                current.hoursJSON = incoming.hoursJSON
                current.tags = incoming.tags
                current.photoURL = incoming.photoURL
                current.photoRights = incoming.photoRights
                current.source = incoming.source
                current.lastVerifiedDate = incoming.lastVerifiedDate
                current.isPublished = incoming.isPublished
                current.updatedAt = Date()
            } else {
                context.insert(incoming)
            }
        }
        try? context.save()
    }
}
