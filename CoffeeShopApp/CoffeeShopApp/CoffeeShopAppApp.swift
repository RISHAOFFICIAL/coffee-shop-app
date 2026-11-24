import SwiftUI
import SwiftData

/// Cupmarks, native iOS.
/// Stage 6 build plan (approved Oct 22, 2026): Apple only, SwiftUI, iOS 26.
/// Sprint 1 wires the SwiftData store, the directory pipeline, and the
/// check in services into the app. The first Xcode Cloud build is the
/// compile verification; this environment has no Swift compiler.
@main
struct CoffeeShopAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    @StateObject private var directoryStore: DirectoryStore
    @StateObject private var locationService: LocationService
    @StateObject private var checkInManager: CheckInManager
    @StateObject private var authManager: AuthManager
    @StateObject private var syncManager: SyncManager

    init() {
        let container = Self.makeContainer()
        self.container = container
        let locationService = LocationService()
        let directoryStore = DirectoryStore(context: container.mainContext)
        let checkInManager = CheckInManager(
            context: container.mainContext,
            locationService: locationService,
            notificationService: NotificationService.shared
        )
        let authManager = AuthManager()
        let syncManager = SyncManager(context: container.mainContext, auth: authManager)
        _directoryStore = StateObject(wrappedValue: directoryStore)
        _locationService = StateObject(wrappedValue: locationService)
        _checkInManager = StateObject(wrappedValue: checkInManager)
        _authManager = StateObject(wrappedValue: authManager)
        _syncManager = StateObject(wrappedValue: syncManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environmentObject(directoryStore)
                .environmentObject(locationService)
                .environmentObject(checkInManager)
                .environmentObject(authManager)
                .environmentObject(syncManager)
                .environmentObject(NotificationService.shared)
                .task {
                    await directoryStore.load()
                    checkInManager.startMonitoring()
                    checkInManager.cleanupOrphanedPhotos()
                    await syncManager.restoreSession()
                }
        }
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Shop.self,
            Visit.self,
            WantToGoEntry.self,
            Companion.self,
            UserSettings.self,
            DismissedArrival.self,
            SyncedDeletion.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            // If the persistent store cannot open, fall back to an
            // in-memory store so the app still runs. Data will not
            // persist in that state; the failure is logged, not hidden.
            // The in-memory fallback uses try! on purpose (reviewed in
            // Sprint 7): it touches no disk, runs no migration, and can
            // only fail on a schema definition error, which would fail
            // the same way in development and never from device state.
            // With no store at all the app cannot run, so there is no
            // graceful state past this point.
            print("Persistent store failed to open, using in-memory store: \(error.localizedDescription)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}
