import SwiftUI
import SwiftData
import CoreLocation

/// Manual check in (Flow D, Story S7): search or pick from nearby shops,
/// tap the shop, tap Check In. Target time is under 20 seconds. The final
/// row adds a shop by typed name, flagged unverified.
struct ManualCheckInView: View {
    @Query(filter: #Predicate<Shop> { $0.isPublished }, sort: \Shop.name) private var shops: [Shop]
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedShop: Shop?
    @State private var showTypedName = false

    private var results: [Shop] {
        let criteria = ShopFilterCriteria(searchText: searchText)
        return ShopFilter.apply(shops, criteria: criteria, userLocation: locationService.lastLocation)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                List {
                    ForEach(results) { shop in
                        Button {
                            selectedShop = shop
                        } label: {
                            HStack {
                                ShopRowView(
                                    shop: shop,
                                    distanceText: shop.distanceText(from: locationService.lastLocation)
                                )
                                if selectedShop?.id == shop.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.appAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Add This Shop By Name") {
                        showTypedName = true
                    }
                    .foregroundStyle(.appAccent)
                }
                .listStyle(.plain)
                if let selectedShop {
                    VStack(spacing: 12) {
                        Text(selectedShop.name)
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        Button("Check In") {
                            checkInManager.manualCheckIn(shop: selectedShop)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(CoffeeSpacing.screenMargin)
                    .background(Color.appSurface)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .sheet(isPresented: $showTypedName) {
                TypedNameCheckInView(
                    coordinate: locationService.lastLocation?.coordinate
                ) {
                    dismiss()
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.appTextSecondary)
            TextField("Search shops or neighborhoods", text: $searchText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: CoffeeSpacing.minTapTarget)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
        .padding(CoffeeSpacing.screenMargin)
    }
}
