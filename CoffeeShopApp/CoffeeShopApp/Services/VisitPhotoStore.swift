import Foundation
import UIKit

/// On device storage for visit photos (Story S8). A photo file lives in
/// the app's Application Support directory under VisitPhotos, named after
/// the visit it belongs to. The Visit model stores only the filename, so
/// the photo never travels with a share and never leaves the phone except
/// through the owner's own sync in Sprint 6. A failed save or load never
/// blocks the visit: callers treat a missing photo as no photo.
enum VisitPhotoStore {
    static let directoryName = "VisitPhotos"
    /// Photos are stored no larger than this on the long edge, so a visit
    /// photo stays small on disk without looking soft on the phone.
    static let maxDimension: CGFloat = 1600

    /// The folder visit photos live in. Tests pass a temporary base URL;
    /// the app uses Application Support. Application Support always
    /// exists on iOS; the temporary directory fallback only guards the
    /// lookup itself, so this never crashes on a missing folder list.
    static func directoryURL(baseURL: URL? = nil) -> URL {
        let base = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func filename(for visitID: UUID) -> String {
        "\(visitID.uuidString).jpg"
    }

    /// The draft file a picked photo is written to while the Add Memory
    /// sheet is still open. Saving the sheet moves the draft into place;
    /// cancelling deletes it, so an existing photo is never overwritten
    /// by a photo the user did not keep.
    static func draftFilename(for visitID: UUID) -> String {
        "\(visitID.uuidString)-draft.jpg"
    }

    /// Saves the photo for a visit, downscaling large images first.
    /// Returns the stored filename. Throws on any write failure; the
    /// caller keeps the visit and reports the photo as not saved.
    @discardableResult
    static func save(_ image: UIImage, for visitID: UUID, baseURL: URL? = nil) throws -> String {
        try saveImage(image, filename: filename(for: visitID), baseURL: baseURL)
    }

    /// Saves a picked photo as a draft while the sheet is still open.
    /// Returns the draft filename.
    @discardableResult
    static func saveDraft(_ image: UIImage, for visitID: UUID, baseURL: URL? = nil) throws -> String {
        try saveImage(image, filename: draftFilename(for: visitID), baseURL: baseURL)
    }

    private static func saveImage(_ image: UIImage, filename: String, baseURL: URL? = nil) throws -> String {
        let directory = directoryURL(baseURL: baseURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = downscaled(image).jpegData(compressionQuality: 0.8) else {
            throw VisitPhotoError.encodingFailed
        }
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic])
        return filename
    }

    /// Loads a stored photo, or nil when there is none or it cannot be read.
    static func load(filename: String, baseURL: URL? = nil) -> UIImage? {
        guard let data = data(filename: filename, baseURL: baseURL) else { return nil }
        return UIImage(data: data)
    }

    /// Loads a stored photo shrunk to a small thumbnail, for list rows.
    /// The full 1600px image is never decoded for a 56pt thumbnail, so
    /// a long Visited list stays light on memory. Nil when there is no
    /// photo or it cannot be read. The aspect ratio is kept.
    static func thumbnail(filename: String, targetSize: CGFloat = 112, baseURL: URL? = nil) -> UIImage? {
        guard let image = load(filename: filename, baseURL: baseURL) else { return nil }
        return downscaled(image, toMaxDimension: targetSize)
    }

    /// Reads the stored photo bytes, or nil when there is none. Sync
    /// uploads these bytes; the image never needs decoding for that.
    static func data(filename: String, baseURL: URL? = nil) -> Data? {
        let url = directoryURL(baseURL: baseURL).appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    /// Saves downloaded photo bytes for a visit (Sprint 6 sync). The
    /// bytes come from the owner's own backup and are stored as-is.
    @discardableResult
    static func saveData(_ data: Data, for visitID: UUID, baseURL: URL? = nil) throws -> String {
        let directory = directoryURL(baseURL: baseURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = filename(for: visitID)
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic])
        return filename
    }

    /// Every photo filename in the folder, for the orphan cleanup.
    /// Missing folders read as empty.
    static func allFilenames(baseURL: URL? = nil) -> [String] {
        let directory = directoryURL(baseURL: baseURL)
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Deletes a stored photo. Missing files are fine; nothing throws.
    static func delete(filename: String, baseURL: URL? = nil) {
        let url = directoryURL(baseURL: baseURL).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Shrinks an image to at most `maxDimension` on the long edge,
    /// keeping its aspect ratio. Smaller images come back unchanged.
    static func downscaled(_ image: UIImage) -> UIImage {
        downscaled(image, toMaxDimension: maxDimension)
    }

    /// Shrinks an image to at most `limit` on the long edge, keeping its
    /// aspect ratio. Smaller images come back unchanged. The thumbnail
    /// loader uses a small limit; saving uses `maxDimension`.
    static func downscaled(_ image: UIImage, toMaxDimension limit: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > limit else { return image }
        let scale = limit / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    enum VisitPhotoError: Error {
        case encodingFailed
    }
}
