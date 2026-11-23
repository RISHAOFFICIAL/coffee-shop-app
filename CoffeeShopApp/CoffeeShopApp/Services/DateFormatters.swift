import Foundation

/// Shared date formatters (Sprint 7). DateFormatter creation is
/// expensive, and the visit history and settings screens were building a
/// fresh one on every render, once per row. These are created once and
/// reused. DateFormatter is not thread safe; every call site is main
/// thread UI code, and these must stay that way.
enum DateFormatters {
    /// "Nov 23, 2026". Used for last verified dates, backup dates, and
    /// the prompts status line.
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// "Nov 23, 2026 at 3:30 PM". Used for visit dates in history rows,
    /// map cards, and the check in confirmation.
    static let mediumDateShortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// "Monday, November 23, 2026 at 3:30 PM". Used on Visit Detail.
    static let fullDateShortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
}
