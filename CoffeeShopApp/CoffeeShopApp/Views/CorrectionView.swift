import SwiftUI
import SwiftData
import CoreLocation

/// Was This The Shop (Screen 7): the correction list after "Not This Shop".
/// The nearest other shops in the directory, plus None Of These, plus adding
/// a shop by typed name, flagged unverified. Picking a shop saves the check
/// in for that shop instead.
struct CorrectionView: View {
    let sourceShop: Shop

    @Query(filter: #Predicate<Shop> { $0.isPublished }, sort: \Shop.name) private var shops: [Shop]
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var showTypedName = false

    private var nearbyShops: [Shop] {
        let center = locationService.lastLocation
            ?? CLLocation(latitude: sourceShop.latitude, longitude: sourceShop.longitude)
        return ShopFilter.nearest(to: center, from: shops, excluding: sourceShop.id, limit: 5)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You were near \(sourceShop.name). Was it one of these instead?")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                }
                Section("Nearby shops") {
                    ForEach(nearbyShops) { shop in
                        Button {
                            checkInManager.correctCheckIn(to: shop)
                            dismiss()
                        } label: {
                            ShopRowView(
                                shop: shop,
                                distanceText: shop.distanceText(from: locationService.lastLocation)
                            )
                        }
                    }
                }
                Section {
                    Button("Add This Shop By Name") {
                        showTypedName = true
                    }
                    .foregroundStyle(.appAccent)
                    Button("None Of These") {
                        checkInManager.dismissCorrection()
                        dismiss()
                    }
                    .foregroundStyle(.appTextSecondary)
                } footer: {
                    Text("A shop added by name is saved as you typed it and marked unverified, so the memory is never lost.")
                }
            }
            .navigationTitle("Was This The Shop?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        checkInManager.dismissCorrection()
                        dismiss()
                    }
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
}

/// Adds a shop by typed name and saves the visit for it. The shop is
/// stored as user entered and labeled unverified everywhere it appears.
struct TypedNameCheckInView: View {
    var coordinate: CLLocationCoordinate2D?
    var onSaved: () -> Void

    @EnvironmentObject private var checkInManager: CheckInManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var neighborhood = ""
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Shop name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Neighborhood", text: $neighborhood)
                        .autocorrectionDisabled()
                    TextField("Address (optional)", text: $address)
                        .autocorrectionDisabled()
                } header: {
                    Text("Add this shop by name")
                } footer: {
                    Text("This saves the visit with the name you typed. The shop is marked unverified until it is added to the Detroit directory.")
                }
                Section {
                    Button("Save Check In") {
                        checkInManager.checkInByTypedName(
                            name: name.trimmingCharacters(in: .whitespaces),
                            neighborhood: neighborhood.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "Detroit"
                                : neighborhood.trimmingCharacters(in: .whitespaces),
                            address: address.trimmingCharacters(in: .whitespaces),
                            coordinate: coordinate
                        )
                        onSaved()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Add By Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
        }
    }
}
