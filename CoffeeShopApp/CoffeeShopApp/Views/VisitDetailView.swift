import SwiftUI
import SwiftData
import MapKit
import UIKit

/// Visit detail (Screen 12), Sprint 4: the shop, the date and time, the
/// neighborhood, how the visit was saved, and every memory jogger that
/// was added, in the same order as the Add Memory sheet. Edit reopens
/// that sheet for the same visit (Story S15). Delete and share arrive
/// with Sprints 5 and 6; this screen shows only what exists, with no
/// dead buttons.
struct VisitDetailView: View {
    let visit: Visit

    @Query private var allCompanions: [Companion]

    @State private var showMemory = false
    @State private var photoImage: UIImage?

    /// Companion names for this visit, in the order they were added.
    private var companionNames: [String] {
        visit.companionIDs.compactMap { id in
            allCompanions.first(where: { $0.id == id })?.name
        }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showMemory = true
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showMemory) {
            AddMemoryView(visit: visit)
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

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: visit.checkedInAt)
    }
}
