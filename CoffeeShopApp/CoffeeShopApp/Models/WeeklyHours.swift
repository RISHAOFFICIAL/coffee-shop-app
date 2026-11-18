import Foundation

/// Weekly opening hours for one shop, stored as JSON on the Shop model and
/// decoded into this value type. The shape matches the Supabase schema
/// comment: one object per weekday, a null day means closed that day.
/// Times are 24 hour "HH:mm" strings. A close time at or before the open
/// time means the shop closes after midnight (overnight hours).
struct DayHours: Codable, Equatable, Hashable {
    var open: String
    var close: String

    /// Minutes after midnight for "HH:mm", or nil when the string is bad.
    private static func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    var openMinutes: Int? { Self.minutes(from: open) }
    var closeMinutes: Int? { Self.minutes(from: close) }

    /// True when the shop closes after midnight (close at or before open).
    var isOvernight: Bool {
        guard let openMinutes, let closeMinutes else { return false }
        return closeMinutes <= openMinutes
    }

    /// True when the given minutes after midnight fall inside these hours,
    /// counting the overnight tail (after midnight, before close).
    func covers(minutesAfterMidnight: Int) -> Bool {
        guard let openMinutes, let closeMinutes else { return false }
        if isOvernight {
            return minutesAfterMidnight >= openMinutes || minutesAfterMidnight < closeMinutes
        }
        return minutesAfterMidnight >= openMinutes && minutesAfterMidnight < closeMinutes
    }

    /// "7 am to 6 pm", used on the shop detail screen.
    var displayText: String {
        "\(Self.displayTime(open)) to \(Self.displayTime(close))"
    }

    static func displayTime(_ time: String) -> String {
        guard let minutes = minutes(from: time) else { return time }
        let hour = minutes / 60
        let minute = minutes % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        if minute == 0 {
            return "\(hour12) \(suffix)"
        }
        return "\(hour12):\(String(format: "%02d", minute)) \(suffix)"
    }
}

struct WeeklyHours: Codable, Equatable, Hashable {
    var mon: DayHours?
    var tue: DayHours?
    var wed: DayHours?
    var thu: DayHours?
    var fri: DayHours?
    var sat: DayHours?
    var sun: DayHours?

    static let empty = WeeklyHours()

    var hasAnyHours: Bool {
        mon != nil || tue != nil || wed != nil || thu != nil || fri != nil || sat != nil || sun != nil
    }

    /// Hours for a Calendar weekday (1 is Sunday, 7 is Saturday).
    func hours(forWeekday weekday: Int) -> DayHours? {
        switch weekday {
        case 1: return sun
        case 2: return mon
        case 3: return tue
        case 4: return wed
        case 5: return thu
        case 6: return fri
        case 7: return sat
        default: return nil
        }
    }

    /// Open Now, computed from real hours and the phone clock (Story S3).
    /// Returns nil when the hours for today are unknown, so callers can say
    /// so honestly instead of guessing. An overnight spill from yesterday
    /// (a shop that closed after midnight) counts as open.
    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool? {
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let today = hours(forWeekday: weekday)
        let yesterdayWeekday = weekday == 1 ? 7 : weekday - 1
        let yesterday = hours(forWeekday: yesterdayWeekday)

        if let today, today.covers(minutesAfterMidnight: minutes) {
            return true
        }
        if let yesterday, yesterday.isOvernight, yesterday.covers(minutesAfterMidnight: minutes) {
            return true
        }
        if today == nil && yesterday == nil {
            return nil
        }
        return false
    }

    /// "until 6 pm" when open now, used on cards and detail. Nil when the
    /// shop is closed or its hours are unknown.
    func closingText(at date: Date, calendar: Calendar = .current) -> String? {
        guard isOpen(at: date, calendar: calendar) == true else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let today = hours(forWeekday: weekday), today.covers(minutesAfterMidnight: minutes) {
            return "until \(DayHours.displayTime(today.close))"
        }
        let yesterdayWeekday = weekday == 1 ? 7 : weekday - 1
        if let yesterday = hours(forWeekday: yesterdayWeekday), yesterday.isOvernight {
            return "until \(DayHours.displayTime(yesterday.close))"
        }
        return nil
    }

    /// One line per day for the shop detail screen, Monday first.
    func summaryLines() -> [(day: String, text: String)] {
        [
            ("Mon", mon?.displayText ?? "Closed"),
            ("Tue", tue?.displayText ?? "Closed"),
            ("Wed", wed?.displayText ?? "Closed"),
            ("Thu", thu?.displayText ?? "Closed"),
            ("Fri", fri?.displayText ?? "Closed"),
            ("Sat", sat?.displayText ?? "Closed"),
            ("Sun", sun?.displayText ?? "Closed"),
        ]
    }
}
