import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Visited Map (Screen 10, Story S9): the same visited shops as pins, one
/// pin per shop at its most recent visit. Tapping a pin previews the visit
/// and opens Visit Detail. A visit whose shop row is missing has no pin;
/// it still shows in the list.
struct VisitedMapView: View {
    @Query(sort: \Visit.checkedInAt, order: .reverse) private var visits: [Visit]
    @Query private var shops: [Shop]
    @EnvironmentObject private var locationService: LocationService

    @State private var selectedVisitID: UUID?
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: DetroitCenter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        )
    )
    @State private var didCenterOnVisits = false

    /// The most recent visit per shop, newest first, with a shop row to
    /// pin. One pin per shop, even when she has been there many times.
    private var pinnedVisits: [PinnedVisit] {
        let shopsByID = Dictionary(uniqueKeysWithValues: shops.map { ($0.id, $0) })
        var seen: Set<UUID> = []
        var pinned: [PinnedVisit] = []
        for visit in visits {
            guard !seen.contains(visit.shopID),
                  let shop = shopsByID[visit.shopID] else { continue }
            seen.insert(visit.shopID)
            pinned.append(PinnedVisit(visit: visit, shop: shop))
        }
        return pinned
    }

    private var selectedPinned: PinnedVisit? {
        guard let selectedVisitID else { return nil }
        return pinnedVisits.first { $0.visit.id == selectedVisitID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                ForEach(pinnedVisits) { pinned in
                    Annotation(pinned.shop.name, coordinate: pinned.shop.coordinate) {
                        Button {
                            selectedVisitID = pinned.visit.id
                        } label: {
                            ShopPinView(shop: pinned.shop, isSelected: selectedVisitID == pinned.visit.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tap to preview this visit")
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
                if let selected = selectedPinned {
                    NavigationLink(value: selected.visit.id) {
                        VisitedPlaceCardView(
                            visit: selected.visit,
                            shop: selected.shop,
                            onClose: { selectedVisitID = nil }
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, CoffeeSpacing.screenMargin)
                    .padding(.bottom, 8)
                }
            }
            .onAppear {
                centerOnVisitsIfNeeded()
                locationService.requestOneShotLocation()
            }
        }
    }

    private func centerOnVisitsIfNeeded() {
        guard !didCenterOnVisits, let first = pinnedVisits.first else { return }
        didCenterOnVisits = true
        cameraPosition = .region(
            MKCoordinateRegion(
                center: first.shop.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )
    }
}

/// One pin on the Visited map: the shop and its most recent visit.
struct PinnedVisit: Identifiable {
    var visit: Visit
    var shop: Shop

    var id: UUID { visit.id }
}

/// The pin preview card on the Visited map: name, neighborhood, the most
/// recent visit date, and the tap hint. Tapping opens Visit Detail.
struct VisitedPlaceCardView: View {
    let visit: Visit
    let shop: Shop
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shop.name)
                        .font(.coffeeCardTitle)
                        .foregroundStyle(.appText)
                        .lineLimit(1)
                    if shop.isSample {
                        SampleBadge()
                    }
                }
                Text("\(shop.neighborhood), your most recent visit")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                Text(formattedDate)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                Text("Tap to open Visit Detail")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.appTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
        .padding(CoffeeSpacing.screenMargin)
        .contentShape(Rectangle())
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shop.name), \(shop.neighborhood), most recent visit \(formattedDate)")
        .accessibilityHint("Tap to open visit detail")
    }

    private var formattedDate: String {
        DateFormatters.mediumDateShortTime.string(from: visit.checkedInAt)
    }
}
