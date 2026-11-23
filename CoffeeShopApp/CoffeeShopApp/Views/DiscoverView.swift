import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Discover (Screens 2, 3, 4): the map and list of Detroit coffee shops,
/// search by name or neighborhood, and the Open Now, Independent Only, and
/// neighborhood filters. Map and list filter the same array through
/// ShopFilter, so they can never disagree (Story S2).
struct DiscoverView: View {
    @Query(filter: #Predicate<Shop> { $0.isPublished }, sort: \Shop.name) private var shops: [Shop]
    @EnvironmentObject private var directoryStore: DirectoryStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var checkInManager: CheckInManager

    private enum Mode: String, CaseIterable {
        case map = "Map"
        case list = "List"
    }

    @State private var mode: Mode = .map
    @State private var criteria = ShopFilterCriteria()
    @State private var showFilters = false
    @State private var selectedShopID: UUID?
    @State private var showManualCheckIn = false
    @State private var navigationPath = NavigationPath()
    @State private var didCenterOnUser = false
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: DetroitCenter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        )
    )

    private var filteredShops: [Shop] {
        ShopFilter.apply(shops, criteria: criteria, userLocation: locationService.lastLocation)
    }

    private var selectedShop: Shop? {
        guard let selectedShopID else { return nil }
        return shops.first { $0.id == selectedShopID }
    }

    /// True while the directory itself is the thing on screen (loading,
    /// error, or empty), rather than the map or list.
    private var isShowingDirectoryState: Bool {
        switch directoryStore.state {
        case .loading where shops.isEmpty: return true
        case .error where shops.isEmpty: return true
        case .empty: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isShowingDirectoryState {
                    directoryStateView
                } else if mode == .map {
                    ZStack(alignment: .top) {
                        mapView
                        topControls
                    }
                } else {
                    VStack(spacing: 0) {
                        topControls
                        listView
                    }
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { shopID in
                if let shop = shops.first(where: { $0.id == shopID }) {
                    ShopDetailView(shop: shop)
                } else {
                    GoneRecordView(message: "This shop is no longer in the directory.")
                }
            }
            .sheet(isPresented: $showFilters) {
                FiltersView(
                    neighborhoods: ShopFilter.neighborhoods(in: shops),
                    current: criteria
                ) { updated in
                    criteria = updated
                }
            }
            .sheet(isPresented: $showManualCheckIn) {
                ManualCheckInView()
            }
            .onChange(of: locationService.lastLocation) { _, location in
                guard let location, !didCenterOnUser else { return }
                didCenterOnUser = true
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
            .onAppear {
                locationService.requestOneShotLocation()
            }
        }
    }

    // MARK: - Directory states

    @ViewBuilder
    private var directoryStateView: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch directoryStore.state {
            case .loading:
                DirectoryLoadingSkeletonView()
            case .error(let message):
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.appAccent)
                    Text(message)
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Retry") {
                        Task { await directoryStore.retry() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)
                }
            default:
                VStack(spacing: 12) {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 36))
                        .foregroundStyle(.appAccent)
                    Text("No shops in the directory yet.")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            ForEach(filteredShops) { shop in
                Annotation(shop.name, coordinate: shop.coordinate) {
                    Button {
                        selectedShopID = shop.id
                    } label: {
                        ShopPinView(shop: shop, isSelected: selectedShopID == shop.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Tap to preview this shop")
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom) {
            if let shop = selectedShop {
                PlaceCardView(
                    shop: shop,
                    onTap: { navigationPath.append(shop.id) },
                    onClose: { selectedShopID = nil }
                )
                .padding(.horizontal, CoffeeSpacing.screenMargin)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        if filteredShops.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.appAccent)
                Text("No shops match that in Detroit yet.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                    .multilineTextAlignment(.center)
                if let activeFilters = criteria.activeFiltersDescription {
                    Text("With these filters on: \(activeFilters).")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button("Clear Filters") {
                    criteria = ShopFilterCriteria()
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 32)
                Spacer()
            }
        } else {
            List {
                ForEach(filteredShops) { shop in
                    NavigationLink(value: shop.id) {
                        ShopRowView(
                            shop: shop,
                            distanceText: shop.distanceText(from: locationService.lastLocation)
                        )
                    }
                }
                directoryFooter
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
        }
    }

    private var directoryFooter: some View {
        Group {
            if case .loaded(_, let lastUpdated) = directoryStore.state {
                Text(directoryFooterText(lastUpdated: lastUpdated))
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if case .offlineCached(_, let lastUpdated) = directoryStore.state {
                Text(directoryFooterText(lastUpdated: lastUpdated) + " Showing saved shops, it may be out of date.")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func directoryFooterText(lastUpdated: Date) -> String {
        "Directory updated \(DateFormatters.mediumDate.string(from: lastUpdated))."
    }

    // MARK: - Top controls

    private var topControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.appTextSecondary)
                    TextField("Search shops or neighborhoods", text: $criteria.searchText)
                        .font(.coffeeBody)
                        .foregroundStyle(.appText)
                        .autocorrectionDisabled()
                    if !criteria.searchText.isEmpty {
                        Button {
                            criteria.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.appTextSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: CoffeeSpacing.minTapTarget)
                .glassPill()

                Button {
                    showFilters = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.appText)
                            .frame(width: CoffeeSpacing.minTapTarget, height: CoffeeSpacing.minTapTarget)
                            .glassPill()
                        if criteria.openNowOnly || criteria.independentOnly || criteria.neighborhood != nil {
                            Circle()
                                .fill(Color.appAccent)
                                .frame(width: 10, height: 10)
                                .offset(x: -6, y: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filters")
                .accessibilityValue(criteria.activeFiltersDescription ?? "No filters")

                Button("Check In") {
                    showManualCheckIn = true
                }
                .font(.coffeeSecondary.weight(.semibold))
                .foregroundStyle(.appPrimaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: CoffeeSpacing.minTapTarget)
                .background(Color.appPrimary, in: Capsule())
                .accessibilityLabel("Check in manually")
            }

            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            locationBanner
            offlineBanner
            ForEach(checkInManager.recoveryArrivals) { arrival in
                RecoveryCardView(arrival: arrival) {
                    checkInManager.checkInFromRecovery(arrival)
                }
            }
        }
        .padding(.horizontal, CoffeeSpacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, mode == .list ? 8 : 0)
    }

    @ViewBuilder
    private var locationBanner: some View {
        if !locationService.isAuthorized {
            Button {
                openSystemSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                    Text("Location is off. Showing Detroit. Tap to fix in Settings.")
                        .font(.coffeeSecondary.weight(.semibold))
                }
                .foregroundStyle(.appText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .glassPill()
        }
    }

    @ViewBuilder
    private var offlineBanner: some View {
        if case .offlineCached = directoryStore.state {
            Button {
                Task { await directoryStore.retry() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("You are offline. Showing saved shops. Tap to retry.")
                        .font(.coffeeSecondary.weight(.semibold))
                }
                .foregroundStyle(.appText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .glassPill()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// The first load skeleton (Sprint 7): placeholder rows shaped like shop
/// rows, instead of a bare spinner, while the directory loads with no
/// cache. A refresh with cached shops keeps showing the cached list, so
/// this only appears on a first load. The placeholder words are hidden
/// from VoiceOver; the container reads as one loading line. The redacted
/// treatment is static, so Reduce Motion needs no special case here.
struct DirectoryLoadingSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coffee shop name")
                        .font(.coffeeCardTitle)
                    Text("Neighborhood, Independent")
                        .font(.coffeeSecondary)
                    Text("Open Now, until 6 pm")
                        .font(.coffeeSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CoffeeSpacing.screenMargin)
                .padding(.vertical, 12)
                Divider()
            }
            Spacer()
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Detroit shops")
    }
}
