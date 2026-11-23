import SwiftUI
import SwiftData
import CoreLocation
import UIKit

/// Share Preview (Flow F step 2, Story S11): shows exactly what will be
/// sent, shop name, address, rating, and the note when it is included, and
/// lets her remove the note before sending without deleting it from her
/// visit. Tapping Share This Shop opens the phone share sheet; she picks
/// the app and sends it herself. The app never sends anything on its own.
struct SharePreviewView: View {
    let visit: Visit
    var coordinate: CLLocationCoordinate2D?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var includeNote: Bool
    @State private var sharerName: String
    @State private var pendingMessage = ""
    @State private var showShareSheet = false

    init(
        visit: Visit,
        coordinate: CLLocationCoordinate2D? = nil,
        includeNoteDefault: Bool,
        sharerNameDefault: String
    ) {
        self.visit = visit
        self.coordinate = coordinate
        _includeNote = State(initialValue: includeNoteDefault)
        _sharerName = State(initialValue: sharerNameDefault)
    }

    /// The exact message that will be sent, rebuilt whenever the note
    /// toggle or the name changes, so the preview never lies.
    private var messageText: String {
        ShareText.message(
            for: visit,
            coordinate: coordinate,
            includeNote: includeNote,
            sharerName: sharerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : sharerName
        )
    }

    private var hasNote: Bool {
        visit.note?.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CoffeeSpacing.screenMargin) {
                    Text("This is exactly what your friend will receive.")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)

                    Text(messageText)
                        .font(.coffeeBody)
                        .foregroundStyle(.appText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CoffeeSpacing.screenMargin)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))

                    if hasNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Include my note", isOn: $includeNote)
                                .font(.coffeeBody)
                                .foregroundStyle(.appText)
                                .tint(.appAccent)
                            if let note = visit.note {
                                Text(note)
                                    .font(.coffeeSecondary)
                                    .foregroundStyle(.appTextSecondary)
                            }
                            Text("Removing the note here only takes it out of this share. It stays on your visit.")
                                .font(.coffeeSecondary)
                                .foregroundStyle(.appTextSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your name")
                            .font(.coffeeCardTitle)
                            .foregroundStyle(.appText)
                        TextField("Your name", text: $sharerName)
                            .font(.coffeeBody)
                            .foregroundStyle(.appText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .frame(minHeight: CoffeeSpacing.minTapTarget)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
                        Text("Shown as Shared by you on the shop page. Optional, and remembered for next time.")
                            .font(.coffeeSecondary)
                            .foregroundStyle(.appTextSecondary)
                    }

                    Button("Share This Shop") {
                        pendingMessage = messageText
                        showShareSheet = true
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Text("You send it yourself from the share sheet. The app never sends anything on its own.")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(CoffeeSpacing.screenMargin)
            }
            .background(Color.appBackground)
            .navigationTitle("Share Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivitySheetView(activityItems: [pendingMessage]) { completed in
                    if completed {
                        saveSharerName()
                        dismiss()
                    }
                }
            }
        }
    }

    /// Remembers the name for the next share. An empty name clears it, so
    /// a future share goes out without a name.
    private func saveSharerName() {
        let settings = UserSettings.current(in: modelContext)
        let trimmed = sharerName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.sharerName = trimmed.isEmpty ? nil : trimmed
        settings.updatedAt = Date()
        try? modelContext.save()
    }
}

/// The system share sheet, as a representable so the preview can close
/// itself after a completed send. The completion only dismisses our
/// preview; the sending itself is the user's tap in the sheet.
struct ActivitySheetView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
