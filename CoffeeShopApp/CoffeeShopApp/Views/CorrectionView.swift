import SwiftUI
import SwiftData
import CoreLocation

/// Was This The Shop (Screen 7): the correction sheet after "Not This
/// Shop" in the check in flow. The list itself is CorrectionListView,
/// shared with the visit edit flow, which pushes the same list from the
/// Add Memory sheet to correct a saved visit's shop (Story S15).
struct CorrectionView: View {
    let sourceShop: Shop

    @EnvironmentObject private var checkInManager: CheckInManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CorrectionListView(sourceShop: sourceShop)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            checkInManager.dismissCorrection()
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// The correction list: the nearest other shops in the directory, plus
/// None Of These, plus adding a shop by typed name, flagged unverified.
/// In the check in flow, picking a shop saves the check in for that shop
/// instead. In the edit flow, picking a shop re-points the visit being
/// edited; CheckInManager decides by whether an edit target is set.
struct CorrectionListView: View {
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

    /// The intro line reads for the flow it is in: a fresh arrival in
    /// the check in flow, a saved visit in the edit flow.
    private var introText: String {
        if checkInManager.correctionTargetVisit != nil {
            return "This visit is saved at \(sourceShop.name). Was it one of these instead?"
        }
        return "You were near \(sourceShop.name). Was it one of these instead?"
    }

    var body: some View {
        List {
            Section {
                Text(introText)
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
        .sheet(isPresented: $showTypedName) {
            TypedNameCheckInView(
                coordinate: locationService.lastLocation?.coordinate
            ) {
                dismiss()
            }
        }
        .onDisappear {
            // Leaving the list without picking a shop ends the edit, so
            // a later correction starts clean. Picking a shop already
            // cleared the target; this is a no-op in that case.
            checkInManager.endVisitCorrection()
        }
    }
}

/// Adds a shop by typed name and saves the visit for it. The shop is
/// stored as user entered and labeled unverified everywhere it appears.
/// In the edit flow the same form re-points the visit being edited.
struct TypedNameCheckInView: View {
    var coordinate: CLLocationCoordinate2D?
    var onSaved: () -> Void

    @EnvironmentObject private var checkInManager: CheckInManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var neighborhood = ""
    @State private var address = ""

    /// In the edit flow this form re-points the visit instead of saving
    /// a check in, so the button and the footer say so.
    private var isEditingVisit: Bool {
        checkInManager.correctionTargetVisit != nil
    }

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
                    Text(isEditingVisit
                        ? "This changes the visit to the shop you typed. The shop is marked unverified until it is added to the Detroit directory."
                        : "This saves the visit with the name you typed. The shop is marked unverified until it is added to the Detroit directory.")
                }
                Section {
                    Button(isEditingVisit ? "Use This Shop" : "Save Check In") {
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
