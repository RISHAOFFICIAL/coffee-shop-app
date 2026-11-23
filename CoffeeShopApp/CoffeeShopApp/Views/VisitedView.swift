import SwiftUI
import SwiftData
import UIKit

/// Visited (Screens 9, 10, 11), Sprint 5: every checked in shop, newest
/// first, also viewable on a map, with the unified search and sharing.
/// Each card shows shop name, neighborhood, relative date, rating when
/// given, one photo when given, tags, and the order and companion when
/// the visit has them. The search screen (Screen 11) is reached from the
/// search button; the map toggle switches to the Visited map (Screen 10).
struct VisitedView: View {
    /// Called when the search screen's Check Want To Go recovery is
    /// picked. The caller switches to the Want To Go tab.
    var onCheckWantToGo: () -> Void = {}

    @Query(sort: \Visit.checkedInAt, order: .reverse) private var visits: [Visit]
    @Query private var companions: [Companion]
    @Query private var shops: [Shop]
    @Query private var settingsRows: [UserSettings]
    @EnvironmentObject private var checkInManager: CheckInManager

    private enum Mode: String, CaseIterable {
        case list = "List"
        case map = "Map"
    }

    @State private var mode: Mode = .list
    @State private var showManualCheckIn = false
    @State private var showSearch = false
    @State private var shareVisit: Visit?

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    emptyState
                } else if mode == .map {
                    ZStack(alignment: .top) {
                        VisitedMapView()
                        modePicker
                            .padding(.top, 8)
                    }
                } else {
                    VStack(spacing: 0) {
                        modePicker
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        listView
                    }
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("Visited")
            .navigationDestination(for: UUID.self) { visitID in
                if let visit = visits.first(where: { $0.id == visitID }) {
                    VisitDetailView(visit: visit)
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                VisitedSearchView(onCheckWantToGo: onCheckWantToGo)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search Visited")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Check In") {
                        showManualCheckIn = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showManualCheckIn) {
                ManualCheckInView()
            }
            .sheet(item: $shareVisit) { visit in
                SharePreviewView(
                    visit: visit,
                    coordinate: shops.first(where: { $0.id == visit.shopID })?.coordinate,
                    includeNoteDefault: settingsRows.first?.shareNotesByDefault ?? false,
                    sharerNameDefault: settingsRows.first?.sharerName ?? ""
                )
            }
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    private var listView: some View {
        List {
            ForEach(checkInManager.recoveryArrivals) { arrival in
                RecoveryCardView(arrival: arrival) {
                    checkInManager.checkInFromRecovery(arrival)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            ForEach(visits) { visit in
                NavigationLink(value: visit.id) {
                    VisitRowView(
                        visit: visit,
                        companionNames: companionNames(for: visit)
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button("Share") {
                        shareVisit = visit
                    }
                    .tint(.appAccent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private func companionNames(for visit: Visit) -> [String] {
        visit.companionIDs.compactMap { id in
            companions.first(where: { $0.id == id })?.name
        }
    }

    private var emptyState: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "bookmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.appAccent)
                Text("No visits yet")
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                Text("When you check in at a Detroit coffee shop, it lands here with the date and neighborhood, so you never forget a shop you loved.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Check In") {
                    showManualCheckIn = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
                Button("Log A Past Visit") {
                    showManualCheckIn = true
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 32)
            }
        }
    }
}

/// One row in the Visited list: photo when one was saved, shop name,
/// neighborhood and relative date, rating when one was given, tags, and
/// the order and companion when the visit has them. In search results the
/// Matched line sits directly under the title, per the hi-fi spec.
struct VisitRowView: View {
    let visit: Visit
    var companionNames: [String] = []
    var matchedLine: String? = nil

    @State private var photoImage: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(visit.shopName)
                        .font(.coffeeCardTitle)
                        .foregroundStyle(.appText)
                        .lineLimit(1)
                    if visit.isUnverifiedShop {
                        Text("Unverified")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.appChipBackground, in: Capsule())
                    }
                }
                if let matchedLine {
                    Text(matchedLine)
                        .font(.coffeeSecondary.weight(.semibold))
                        .foregroundStyle(.appAccent)
                }
                Text("\(visit.neighborhood), \(relativeDate)")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                if !visit.tags.isEmpty {
                    Text(visit.tags.joined(separator: ", "))
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                        .lineLimit(1)
                }
                if let memoryLine {
                    Text(memoryLine)
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let rating = visit.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.appAccent)
                    Text("\(rating)")
                        .font(.coffeeSecondary.weight(.semibold))
                        .foregroundStyle(.appText)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appTextSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(visit.shopName), \(visit.neighborhood), \(relativeDate)")
        .task(id: visit.photoFilename) {
            if let filename = visit.photoFilename {
                photoImage = VisitPhotoStore.load(filename: filename)
            } else {
                photoImage = nil
            }
        }
    }

    /// "Cappuccino, with Aric", or whichever half the visit has.
    private var memoryLine: String? {
        var parts: [String] = []
        if let order = visit.orderText, !order.isEmpty {
            parts.append(order)
        }
        if !companionNames.isEmpty {
            parts.append("with \(companionNames.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "Today", "Yesterday", "Last Month", "3 Months Ago".
    private var relativeDate: String {
        visit.checkedInAt.formatted(.relative(presentation: .named)).capitalized
    }
}
