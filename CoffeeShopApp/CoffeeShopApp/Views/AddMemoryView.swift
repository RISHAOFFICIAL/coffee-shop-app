import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Add Memory (Screen 8, Stories S8 and S15): the joggers sheet, in the
/// approved order: rating, quick tags for why she liked it, what she
/// ordered, who she was with, photo, note. Every jogger is optional.
/// Closing without saving never touches the visit, which was already
/// saved at check in. The same sheet edits a visit later from Visit
/// Detail, including correcting the shop through the Sprint 3 path.
struct AddMemoryView: View {
    let visit: Visit

    @EnvironmentObject private var checkInManager: CheckInManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Companion.name) private var savedCompanions: [Companion]
    @Query private var shops: [Shop]

    /// Quick tags for why she liked it. A custom tag can be added below;
    /// tags need no typing beyond that, per the S8 acceptance check.
    static let quickTags = [
        "Great coffee",
        "Good wifi",
        "Good for working",
        "Cozy",
        "Good pastries",
        "Friendly staff",
        "Quiet",
        "Good music",
        "Pretty space",
        "Good for groups",
    ]

    @State private var rating: Int?
    @State private var selectedTags: Set<String>
    @State private var customTagText = ""
    @State private var orderText: String
    @State private var selectedCompanionNames: Set<String> = []
    @State private var companionText = ""
    @State private var photoImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pendingDraftFilename: String?
    @State private var photoRemoved = false
    @State private var photoMessage: String?
    @State private var note: String
    @State private var showCorrection = false
    @State private var didSeedCompanions = false
    @State private var didSave = false

    init(visit: Visit) {
        self.visit = visit
        _rating = State(initialValue: visit.rating)
        _selectedTags = State(initialValue: Set(visit.tags))
        _orderText = State(initialValue: visit.orderText ?? "")
        _note = State(initialValue: visit.note ?? "")
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// The shop the correction list starts from: the directory row when
    /// it still exists, otherwise a lightweight copy built from the
    /// visit's own saved shop fields.
    private var correctionSourceShop: Shop {
        if let shop = shops.first(where: { $0.id == visit.shopID }) {
            return shop
        }
        return Shop(
            id: visit.shopID,
            name: visit.shopName,
            address: visit.address,
            neighborhood: visit.neighborhood,
            latitude: DetroitCenter.coordinate.latitude,
            longitude: DetroitCenter.coordinate.longitude,
            kind: .independent,
            hours: .empty,
            source: "Saved visit",
            lastVerifiedDate: visit.checkedInAt,
            isPublished: false,
            isUserEntered: visit.isUnverifiedShop
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    shopHeader
                    ratingSection
                    tagsSection
                    orderSection
                    companionsSection
                    photoSection
                    noteSection
                    Text("Everything here is optional. Your visit is already saved.")
                        .font(.coffeeSecondary)
                        .foregroundStyle(.appTextSecondary)
                }
                .padding(CoffeeSpacing.screenMargin)
            }
            .background(Color.appBackground)
            .navigationTitle("Add A Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showCorrection) {
                CorrectionListView(sourceShop: correctionSourceShop)
            }
            .sheet(isPresented: $showCamera) {
                CameraPickerView(
                    onPhoto: { image in
                        showCamera = false
                        attachPhoto(image)
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
            }
            .onAppear {
                seedCompanionsIfNeeded()
            }
            .onChange(of: savedCompanions) { _, _ in
                seedCompanionsIfNeeded()
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadPickedPhoto(newItem)
                }
            }
            .task {
                if let filename = visit.photoFilename {
                    photoImage = VisitPhotoStore.load(filename: filename)
                }
            }
            .onDisappear {
                // A swipe dismiss after picking a photo still cleans up
                // the draft, so no orphan file is left behind.
                if !didSave, let draft = pendingDraftFilename {
                    VisitPhotoStore.delete(filename: draft)
                }
            }
        }
    }

    // MARK: - Shop header and correction entry

    private var shopHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(visit.shopName)
                .font(.coffeeTitle)
                .foregroundStyle(.appText)
            Text("\(visit.neighborhood), Detroit")
                .font(.coffeeBody)
                .foregroundStyle(.appTextSecondary)
            if visit.isUnverifiedShop {
                Text("Added by you, not verified directory data.")
                    .font(.coffeeSecondary.weight(.semibold))
                    .foregroundStyle(.appAccent)
            }
            Button("Change Shop") {
                checkInManager.beginVisitCorrection(for: visit)
                showCorrection = true
            }
            .font(.coffeeSecondary.weight(.semibold))
            .foregroundStyle(.appAccent)
            .padding(.top, 4)
        }
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Rating")
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = (rating == star) ? nil : star
                    } label: {
                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 30))
                            .foregroundStyle(.appAccent)
                            .frame(width: CoffeeSpacing.minTapTarget, height: CoffeeSpacing.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Quick tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Why did you like it?")
            FlowLayout(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        ChipView(text: tag, isSelected: selectedTags.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("Add your own tag", text: $customTagText)
                    .font(.coffeeBody)
                    .foregroundStyle(.appText)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: CoffeeSpacing.minTapTarget)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
                Button("Add") {
                    addCustomTag()
                }
                .font(.coffeeSecondary.weight(.semibold))
                .foregroundStyle(.appAccent)
                .frame(minHeight: CoffeeSpacing.minTapTarget)
                .disabled(customTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// Preset quick tags plus any custom tags already on this visit, so a
    /// custom tag from an earlier edit stays visible and tappable.
    private var allTags: [String] {
        var tags = Self.quickTags
        for tag in selectedTags where !tags.contains(tag) {
            tags.append(tag)
        }
        return tags
    }

    private func addCustomTag() {
        let trimmed = customTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTags.insert(trimmed)
        customTagText = ""
    }

    // MARK: - Order

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What did you order?")
            TextField("Latte, croissant", text: $orderText)
                .font(.coffeeBody)
                .foregroundStyle(.appText)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: CoffeeSpacing.minTapTarget)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
        }
    }

    // MARK: - Companions

    private var companionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Who were you with?")
            if !allCompanionNames.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(allCompanionNames, id: \.self) { name in
                        Button {
                            if selectedCompanionNames.contains(name) {
                                selectedCompanionNames.remove(name)
                            } else {
                                selectedCompanionNames.insert(name)
                            }
                        } label: {
                            ChipView(text: name, isSelected: selectedCompanionNames.contains(name))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a name", text: $companionText)
                    .font(.coffeeBody)
                    .foregroundStyle(.appText)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: CoffeeSpacing.minTapTarget)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
                Button("Add") {
                    addCompanionName()
                }
                .font(.coffeeSecondary.weight(.semibold))
                .foregroundStyle(.appAccent)
                .frame(minHeight: CoffeeSpacing.minTapTarget)
                .disabled(companionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Names stay in this app. Contacts are never imported.")
                .font(.coffeeSecondary)
                .foregroundStyle(.appTextSecondary)
        }
    }

    /// Saved companion names plus names picked for this visit, so a name
    /// typed on a previous visit stays tappable here.
    private var allCompanionNames: [String] {
        var names = savedCompanions.map(\.name)
        for name in selectedCompanionNames where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    private func addCompanionName() {
        let trimmed = companionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedCompanionNames.insert(trimmed)
        companionText = ""
    }

    /// Seeds the picked companions from the visit's saved companion IDs,
    /// once the Companion rows have loaded. Waits for the query when the
    /// visit has companions but the rows are not in yet.
    private func seedCompanionsIfNeeded() {
        guard !didSeedCompanions else { return }
        guard !savedCompanions.isEmpty || visit.companionIDs.isEmpty else { return }
        didSeedCompanions = true
        selectedCompanionNames = Set(
            visit.companionIDs.compactMap { id in
                savedCompanions.first(where: { $0.id == id })?.name
            }
        )
    }

    // MARK: - Photo

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Photo")
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
                    .accessibilityLabel("Photo saved with this visit")
            }
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Text(photoImage == nil ? "Choose From Library" : "Choose A Different Photo")
                    .font(.coffeeButton)
                    .foregroundStyle(.appAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: CoffeeSpacing.minTapTarget)
                    .background(Color.appChipBackground, in: RoundedRectangle(cornerRadius: CoffeeSpacing.buttonRadius))
            }
            if cameraAvailable {
                Button("Take A Photo") {
                    showCamera = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if photoImage != nil {
                Button("Remove Photo", role: .destructive) {
                    removePhoto()
                }
                .font(.coffeeSecondary.weight(.semibold))
                .frame(minHeight: CoffeeSpacing.minTapTarget)
            }
            if let photoMessage {
                Text(photoMessage)
                    .font(.coffeeSecondary)
                    .foregroundStyle(.appTextSecondary)
            }
        }
    }

    /// Loads a photo picked from the library and writes it as a draft.
    /// Any failure shows a plain message and leaves the visit alone: a
    /// failed or denied photo never blocks the visit.
    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoMessage = "That photo could not be read. Your visit is still saved."
                return
            }
            attachPhoto(image)
        } catch {
            photoMessage = "That photo could not be read. Your visit is still saved."
        }
    }

    private func attachPhoto(_ image: UIImage) {
        do {
            pendingDraftFilename = try VisitPhotoStore.saveDraft(image, for: visit.id)
            photoRemoved = false
            photoImage = image
            photoMessage = nil
        } catch {
            photoMessage = "That photo could not be saved. Your visit is still saved."
        }
    }

    private func removePhoto() {
        photoImage = nil
        photoRemoved = true
        photoMessage = nil
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Note")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $note)
                    .font(.coffeeBody)
                    .foregroundStyle(.appText)
                    .frame(minHeight: 100)
                    .padding(8)
                if note.isEmpty {
                    Text("Anything else to remember?")
                        .font(.coffeeBody)
                        .foregroundStyle(.appTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: CoffeeSpacing.cardRadius))
        }
    }

    // MARK: - Save and cancel

    private func save() {
        didSave = true
        var finalPhotoFilename = visit.photoFilename
        if photoRemoved {
            if let old = visit.photoFilename {
                VisitPhotoStore.delete(filename: old)
            }
            if let draft = pendingDraftFilename {
                VisitPhotoStore.delete(filename: draft)
            }
            finalPhotoFilename = nil
        } else if let draft = pendingDraftFilename,
                  let draftImage = VisitPhotoStore.load(filename: draft) {
            // The draft becomes the visit photo. If that final write
            // fails, the previous photo (if any) is kept instead.
            finalPhotoFilename = (try? VisitPhotoStore.save(draftImage, for: visit.id)) ?? visit.photoFilename
            VisitPhotoStore.delete(filename: draft)
        }
        checkInManager.saveMemory(
            for: visit,
            rating: rating,
            tags: Array(selectedTags),
            orderText: orderText,
            note: note,
            companionNames: Array(selectedCompanionNames),
            photoFilename: finalPhotoFilename
        )
        dismiss()
    }

    private func cancel() {
        if let draft = pendingDraftFilename {
            VisitPhotoStore.delete(filename: draft)
        }
        dismiss()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.coffeeCardTitle)
            .foregroundStyle(.appText)
    }
}

/// The system camera, wrapped for SwiftUI. Shown only where the device
/// has a camera; the library picker is always available.
struct CameraPickerView: UIViewControllerRepresentable {
    var onPhoto: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhoto: onPhoto, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPhoto: (UIImage) -> Void
        let onCancel: () -> Void

        init(onPhoto: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onPhoto(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
