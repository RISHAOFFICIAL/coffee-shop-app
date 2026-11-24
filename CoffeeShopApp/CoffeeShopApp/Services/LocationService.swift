import Foundation
import CoreLocation

/// Wraps Core Location for the arrival prompt system (Sprint 3).
/// The app monitors the nearest shops up to the iOS limit of 20 regions
/// and refreshes that set as the user moves, using significant location
/// changes rather than continuous tracking (build spec). No location is
/// uploaded: region events are processed on the device only.
final class LocationService: NSObject, ObservableObject {
    /// iOS allows 20 monitored regions per app.
    static let maxMonitoredRegions = 20
    /// A shop region covers the shop and the sidewalk outside it.
    static let regionRadius: CLLocationDistance = 100

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?

    /// Called with the shop id when the user enters a monitored shop region.
    var onRegionEntry: ((UUID) -> Void)?
    /// Called with the shop id when the user leaves a monitored shop region.
    var onRegionExit: ((UUID) -> Void)?
    /// Called when a significant move suggests the nearest 20 shops changed.
    var onSignificantMove: (() -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var canPromptWhileClosed: Bool {
        authorizationStatus == .authorizedAlways
    }

    /// Plain language status for Settings and the Discover banner.
    var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not set yet"
        case .restricted:
            return "Restricted by the phone"
        case .denied:
            return "Off. Prompts cannot appear."
        case .authorizedWhenInUse:
            return "While Using The App. Prompts only appear while the app is open."
        case .authorizedAlways:
            return "Always. Prompts can appear while the app is closed."
        @unknown default:
            return "Unknown"
        }
    }

    /// Step 1 of the staged permission flow: while using the app first.
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Step 2, only after the plain explanation in first launch: always
    /// access is what lets prompts appear when the app is closed.
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// One location fix for map centering. No continuous tracking.
    func requestOneShotLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    func startSignificantChangeMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopSignificantChangeMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// Monitors the nearest shops to `center`, up to the iOS limit of 20.
    /// Sample shops are never monitored. Shops already monitored stay
    /// monitored; only the changed set is touched.
    func refreshMonitoredRegions(near shops: [Shop], center: CLLocation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              isAuthorized else { return }
        let nearest = shops
            .filter { !$0.isSample && $0.isPublished }
            .sorted { ($0.distance(from: center) ?? .greatestFiniteMagnitude) < ($1.distance(from: center) ?? .greatestFiniteMagnitude) }
            .prefix(Self.maxMonitoredRegions)
        let wantedIDs = Set(nearest.map { $0.id.uuidString })
        for region in manager.monitoredRegions {
            if !wantedIDs.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
        }
        let monitoredIDs = Set(manager.monitoredRegions.map(\.identifier))
        for shop in nearest where !monitoredIDs.contains(shop.id.uuidString) {
            let region = CLCircularRegion(
                center: shop.coordinate,
                radius: Self.regionRadius,
                identifier: shop.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    func stopAllMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        stopSignificantChangeMonitoring()
    }

    var monitoredShopCount: Int {
        manager.monitoredRegions.count
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            requestOneShotLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        lastLocation = latest
        onSignificantMove?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let shopID = UUID(uuidString: region.identifier) else { return }
        onRegionEntry?(shopID)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let shopID = UUID(uuidString: region.identifier) else { return }
        onRegionExit?(shopID)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // On launch, iOS tells us which regions we are already inside.
        // Treat that as an arrival so a stay that started before launch
        // still gets its brief stay check.
        guard state == .inside, let shopID = UUID(uuidString: region.identifier) else { return }
        onRegionEntry?(shopID)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Region monitoring failed: \(error.localizedDescription)")
    }
}
