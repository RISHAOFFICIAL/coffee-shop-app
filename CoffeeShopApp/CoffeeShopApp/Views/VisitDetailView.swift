import SwiftUI
import MapKit

/// Visit detail (Screen 12), Sprint 3 minimal version: the shop, the date
/// and time, the neighborhood, and how the visit was saved. Edit, delete,
/// share, and the full jogger display arrive with Sprints 4 and 5; this
/// screen shows only what exists, with no dead buttons.
struct VisitDetailView: View {
    let visit: Visit

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
                    }
                }
                if !visit.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tags")
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
                if let note = visit.note, !note.isEmpty {
                    detailRow(title: "Note", text: note)
                }
            }
            .padding(CoffeeSpacing.screenMargin)
        }
        .background(Color.appBackground)
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
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
