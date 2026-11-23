import SwiftUI
import SwiftData

/// Want To Go (Screen 13, Story S12), Sprint 5: shops saved from a shared
/// recommendation or from Discover, separate from Visited. Each card shows
/// who shared it, open status and distance when the shop is in the
/// directory and location is on, and Directions and Check In There.
/// Checking in moves the shop into Visited and off this list; nothing
/// else does. A shop saved here is never a visit.
struct WantToGoView: View {
    /// Called when the empty state button is picked. The caller switches
    /// to the Discover tab.
    var onShowDiscover: () -> Void = {}

    @Query(sort: \WantToGoEntry.addedAt, order: .reverse) private var entries: [WantToGoEntry]
    @Query private var shops: [Shop]
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var checkInManager: CheckInManager
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.modelContext) private var modelContext

    @State private var showSignIn = false

    /// The banner shows only when signed out with visits waiting for
    /// backup (Flow H step 4). It sits above the list either way, so
    /// it is visible in both the empty and filled states.
    private var showBackupBanner: Bool {
        !syncManager.isSignedIn && syncManager.unsyncedVisitCount > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showBackupBanner {
                    BackupBannerView { showSignIn = true }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                Group {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(entries) { entry in
                                WantToGoRowView(
                                    entry: entry,
                                    shop: shops.first { $0.id == entry.shopID },
                                    distanceText: distanceText(for: entry),
                                    onDirections: { openDirections(for: entry) },
                                    onCheckIn: { checkInManager.checkInFromWantToGo(entry) }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .swipeActions(edge: .trailing) {
                                    Button("Remove", role: .destructive) {
                                        WantToGoStore(context: modelContext).remove(entry)
                                    }
                                }
                            }
                            Text("Not visited yet. A shop moves to Visited only when you check in there.")
                                .font(.coffeeSecondary)
                                .foregroundStyle(.appTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.appBackground)
                    }
                }
                .background(Color.appBackground)
                .navigationTitle("Want To Go")
                .sheet(isPresented: $showSignIn) {
                    SignInView()
                }
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "heart")
                    .font(.system(size: 44))
                    .foregroundStyle(.appAccent)
                Text("Nothing saved yet")
                    .font(.coffeeTitle)
                    .foregroundStyle(.appText)
                Text("Shops friends share with you land here, and so do shops you save from Discover. Nothing here is a visit until you check in there.")
                    .font(.coffeeBody)
                    .foregroundStyle(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Find More In Discover") {
                    onShowDiscover()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
            }
        }
    }

    private func distanceText(for entry: WantToGoEntry) -> String? {
        guard let shop = shops.first(where: { $0.id == entry.shopID }) else { return nil }
        return shop.distanceText(from: locationService.lastLocation)
    }

    private func openDirections(for entry: WantToGoEntry) {
        if let shop = shops.first(where: { $0.id == entry.shopID }) {
            Directions.open(coordinate: shop.coordinate, name: shop.name)
        } else if !entry.address.isEmpty {
            Directions.open(address: entry.address, name: entry.shopName)
        }
    }
}

/// One card in the Want To Go list: name, neighborhood and open status,
/// who shared it, their note when they left one, distance when known, and
/// the Directions and Check In There buttons.
struct WantToGoRowView: View {
    let entry: WantToGoEntry
    var shop: Shop?
    var distanceText: String?
    var onDirections: () -> Void
    var onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.shopName)
                    .font(.coffeeCardTitle)
                    .foregroundStyle(.appText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let shop {
                        Text(entry.neighborhood + ",")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                        OpenStatusView(shop: shop)
                    } else {
                        Text(entry.neighborhood)
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                    if let distanceText {
                        Text(distanceText + " away")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }
                }
                if let sharedBy = entry.sharedBy {
                    Text("Shared by \(sharedBy)")
                        .font(.coffeeSecondary.weight(.semibold))
                        .foregroundStyle(.appAccent)
                } else {
                    Text("Saved from Discover")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                }
                if let note = entry.noteFromSharer, !note.isEmpty {
                    Text(note)
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                        .italic()
                }
            }
            HStack(spacing: 12) {
                Button("Directions", action: onDirections)
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appAccent)
                    .padding(.horizontal, 14)
                    .frame(height: CoffeeSpacing.minTapTarget)
                    .background(Color.appChipBackground, in: Capsule())
                Button("Check In There", action: onCheckIn)
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appPrimaryText)
                    .padding(.horizontal, 14)
                    .frame(height: CoffeeSpacing.minTapTarget)
                    .background(Color.appPrimary, in: Capsule())
                Spacer()
            }
        }
        .padding(CoffeeSpacing.screenMargin)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
    }
}
