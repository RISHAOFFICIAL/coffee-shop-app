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
    /// The name shown as "Shared by" on a shared shop, remembered from
    /// the last share. Nil means shares go out without a name.
    var sharerName: String?
    var lastPromptDate: Date?
    var lastPromptShopName: String?
    /// The last successful backup, for the Settings status line.
    var lastSyncAt: Date?
    /// The counted confirmation from the last sync, for example
    /// "12 visits backed up, 1 duplicate merged."
    var lastSyncSummary: String?
    /// True once the Visited backup reminder card has been dismissed.
    /// The card appears only after the third check in, and only once
    /// (Flow H step 1).
    var backupReminderDismissed: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        hasCompletedFirstLaunch: Bool = false,
        autoCheckInPromptsEnabled: Bool = true,
        shareNotesByDefault: Bool = false,
        sharerName: String? = nil,
        lastPromptDate: Date? = nil,
        lastPromptShopName: String? = nil,
        lastSyncAt: Date? = nil,
        lastSyncSummary: String? = nil,
        backupReminderDismissed: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hasCompletedFirstLaunch = hasCompletedFirstLaunch
        self.autoCheckInPromptsEnabled = autoCheckInPromptsEnabled
        self.shareNotesByDefault = shareNotesByDefault
        self.sharerName = sharerName
        self.lastPromptDate = lastPromptDate
        self.lastPromptShopName = lastPromptShopName
        self.lastSyncAt = lastSyncAt
        self.lastSyncSummary = lastSyncSummary
        self.backupReminderDismissed = backupReminderDismissed
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
