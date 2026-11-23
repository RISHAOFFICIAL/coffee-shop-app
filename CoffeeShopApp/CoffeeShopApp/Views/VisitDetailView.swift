import SwiftUI
import SwiftData
import MapKit
import UIKit

/// Visit detail (Screen 12), Sprint 5: the shop, the date and time, the
/// neighborhood, how the visit was saved, and every memory jogger that
/// was added, in the same order as the Add Memory sheet. Edit reopens
/// that sheet for the same visit (Story S15). Share opens the share
/// preview (Story S11); Directions and Check In Again are here too; and
/// the Visits To This Shop section is the entry point to the shop's full
/// history. Delete (Sprint 6, Story S13) sits at the bottom of the
/// actions, with a confirmation naming the shop and date, and the Undo
/// bar appears in Visited after it runs.
struct VisitDetailView: View {
    let visit: Visit

    @Query private var allCompanions: [Companion]
    @Query private var allVisits: [Visit]
    @Query private var shops: [Shop]
    @Query private var settingsRows: [UserSettings]
    @EnvironmentObject private var checkInManager: CheckInManager
    @Environment(\.dismiss) private var dismiss

    @State private var showMemory = false
    @State private var showShare = false
    @State private var showDeleteConfirm = false
    @State private var photoImage: UIImage?

    /// Companion names for this visit, in the order they were added.
    private var companionNames: [String] {
        visit.companionIDs.compactMap { id in
            allCompanions.first(where: { $0.id == id })?.name
        }
    }

    /// Every visit to this shop, newest first. The full per shop history
    /// screen is Story S16, post version 1; this section is the entry
    /// point to it, and each row opens that visit.
    private var shopVisits: [Visit] {
        allVisits
            .filter { $0.shopID == visit.shopID }
            .sorted { $0.checkedInAt > $1.checkedInAt }
    }

    /// The directory shop for this visit, for directions and Check In
    /// Again. Nil only when the shop row is missing, which should not
    /// happen for a saved visit.
    private var shop: Shop? {
        shops.first { $0.id == visit.shopID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CoffeeSpacing.screenMargin) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(visit.shopName)
                        .font(.coffeeTitle)
                        .foregroundStyle(.appText)
                    Text("\(visit.neighborhood), Detroit")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                    Text(formattedDate)
                        .font(.coffeeBody)
                        .foregroundStyle(.appText)
                    Text(visit.source.displayText)
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                    if visit.isUnverifiedShop {
                        Text("Added by you, not verified directory data.")
                            .font(.coffeeSecondary.weight(.semibold))
                            .foregroundStyle(.appAccent)
                    }
                }
                if !visit.address.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        Text(visit.address)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                    }
                }
                actions
                if shopVisits.count > 1 {
                    historySection
                }
                if visit.joggerCount == 0 {
                    Button("Add A Memory") {
                        showMemory = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if let rating = visit.rating {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rating")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundStyle(.appAccent)
                            }
                        }
                        .accessibilityLabel("Rated \(rating) out of 5 stars")
                    }
                }
                if !visit.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Why you liked it")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        FlowLayout(spacing: 8) {
                            ForEach(visit.tags, id: \.self) { tag in
                                ChipView(text: tag)
                            }
                        }
                    }
                }
                if let orderText = visit.orderText, !orderText.isEmpty {
                    detailRow(title: "Ordered", text: orderText)
                }
                if !companionNames.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Who you were with")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        FlowLayout(spacing: 8) {
                            ForEach(companionNames, id: \.self) { name in
                                ChipView(text: name)
                            }
                        }
                    }
                }
                if let photoImage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Photo")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        Image(uiImage: photoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
                            .accessibilityLabel("Photo saved with this visit")
                    }
                }
                if let note = visit.note, !note.isEmpty {
                    detailRow(title: "Note", text: note)
                }
            }
            .padding(CoffeeSpacing.screenMargin)
        }
        .background(Color.appBackground)
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share this shop")
                Button("Edit") {
                    showMemory = true
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showMemory) {
            AddMemoryView(visit: visit)
        }
        .sheet(isPresented: $showShare) {
            SharePreviewView(
                visit: visit,
                coordinate: shop?.coordinate,
                includeNoteDefault: settingsRows.first?.shareNotesByDefault ?? false,
                sharerNameDefault: settingsRows.first?.sharerName ?? ""
            )
        }
        .task(id: visit.photoFilename) {
            if let filename = visit.photoFilename {
                photoImage = VisitPhotoStore.load(filename: filename)
            } else {
                photoImage = nil
            }
        }
    }

    private func detailRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            Text(text)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
        }
    }

    // MARK: - Actions and history (Sprint 5)

    private var actions: some View {
        VStack(spacing: 12) {
            Button("Share This Shop") {
                showShare = true
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Directions", action: openDirections)
                .buttonStyle(SecondaryButtonStyle())
            if let shop {
                Button("Check In Again") {
                    checkInManager.manualCheckIn(shop: shop)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Delete This Visit", role: .destructive) {
                showDeleteConfirm = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .confirmationDialog(
            "Delete this visit?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Visit", role: .destructive) {
                checkInManager.deleteVisit(visit)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your visit to \(visit.shopName) on \(shortDate). You can undo it for a few seconds after.")
        }
    }

    private var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: visit.checkedInAt)
    }

    /// Every visit to this shop, newest first, each row opening that
    /// visit. The current visit is marked so the list reads as history,
    /// not as duplicates.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visits to this shop")
                .font(.coffeeCardTitle)
                .foregroundStyle(.appText)
            Text(historySummary)
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
            ForEach(shopVisits) { shopVisit in
                if shopVisit.id == visit.id {
                    historyRow(for: shopVisit)
                } else {
                    NavigationLink(value: shopVisit.id) {
                        historyRow(for: shopVisit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// One row in the history list. Other visits get a chevron and
    /// navigate; the current visit is plain text, because tapping it
    /// would only open the screen already showing.
    private func historyRow(for shopVisit: Visit) -> some View {
        HStack {
            Text(historyDate(for: shopVisit))
                .font(.coffeeBody)
                .foregroundStyle(.appText)
            if shopVisit.id == visit.id {
                Text("This visit")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appChipBackground, in: Capsule())
            }
            Spacer()
            if let rating = shopVisit.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.appAccent)
                    Text("\(rating)")
                        .font(.coffeeSecondary.weight(.semibold))
                        .foregroundStyle(.appText)
                }
            }
            if shopVisit.id != visit.id {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appTextSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Visited 3 times, first on Nov 2, 2026."
    private var historySummary: String {
        let count = shopVisits.count
        guard let first = shopVisits.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Visited \(count) times, first on \(formatter.string(from: first.checkedInAt))."
    }

    private func historyDate(for shopVisit: Visit) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: shopVisit.checkedInAt)
    }

    private func openDirections() {
        if let shop {
            Directions.open(coordinate: shop.coordinate, name: shop.name)
        } else if !visit.address.isEmpty {
            Directions.open(address: visit.address, name: visit.shopName)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: visit.checkedInAt)
    }
}
