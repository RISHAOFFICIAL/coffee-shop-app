import Foundation
import SwiftData

/// App settings, stored on device as a single SwiftData row. There is
/// exactly one row per install; `current(in:)` fetches it or creates it.
@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var hasCompletedFirstLaunch: Bool
    var autoCheckInPromptsEnabled: Bool
    var shareNotesByDefault: Bool
    var lastPromptDate: Date?
    var lastPromptShopName: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        hasCompletedFirstLaunch: Bool = false,
        autoCheckInPromptsEnabled: Bool = true,
        shareNotesByDefault: Bool = false,
        lastPromptDate: Date? = nil,
        lastPromptShopName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hasCompletedFirstLaunch = hasCompletedFirstLaunch
        self.autoCheckInPromptsEnabled = autoCheckInPromptsEnabled
        self.shareNotesByDefault = shareNotesByDefault
        self.lastPromptDate = lastPromptDate
        self.lastPromptShopName = lastPromptShopName
        self.updatedAt = updatedAt
    }

    /// Fetches the single settings row, creating it with defaults when this
    /// is a fresh install.
    @MainActor
    static func current(in context: ModelContext) -> UserSettings {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = UserSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    /// The honest status line under the prompts toggle in Settings.
    var promptsStatusText: String {
        if !autoCheckInPromptsEnabled {
            return "Off. No prompts will appear."
        }
        if let lastPromptDate, let lastPromptShopName {
            if Calendar.current.isDateInToday(lastPromptDate) {
                return "On. Last prompt was today at \(lastPromptShopName)."
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "On. Last prompt was \(formatter.string(from: lastPromptDate)) at \(lastPromptShopName)."
        }
        return "On. No prompt has appeared yet."
    }
}
