import SwiftUI
import SwiftData

/// Visited (Screen 9), Sprint 3 minimal version: every checked in shop,
/// newest first, so a saved visit is visible right after check in (Story
/// S6). The full Sprint 5 version adds the map toggle, unified search with
/// the Matched because line, sharing, and visit history.
struct VisitedView: View {
    @Query(sort: \Visit.checkedInAt, order: .reverse) private var visits: [Visit]
    @EnvironmentObject private var checkInManager: CheckInManager

    @State private var showManualCheckIn = false

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    emptyState
                } else {
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
                                VisitRowView(visit: visit)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("Visited")
            .navigationDestination(for: UUID.self) { visitID in
                if let visit = visits.first(where: { $0.id == visitID }) {
                    VisitDetailView(visit: visit)
                }
            }
            .toolbar {
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

/// One row in the Visited list: shop name, neighborhood, date, and rating
/// when one was given (Sprint 4).
struct VisitRowView: View {
    let visit: Visit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                Text("\(visit.neighborhood), Detroit")
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
                Text(formattedDate)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
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
        .accessibilityLabel("\(visit.shopName), \(visit.neighborhood), \(formattedDate)")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: visit.checkedInAt)
    }
}
