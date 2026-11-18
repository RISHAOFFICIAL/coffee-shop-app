import Foundation
import Testing
@testable import CoffeeShopApp

/// Open Now logic (Story S3): computed from real hours and the phone clock.
/// Fixture week: Mon Nov 16 to Sun Nov 22, 2026, America/Detroit.
struct WeeklyHoursTests {
    private static var detroitCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        return calendar
    }

    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        return detroitCalendar.date(from: components)!
    }

    private static var weekdayHours: WeeklyHours {
        WeeklyHours(
            mon: DayHours(open: "07:00", close: "18:00"),
            tue: DayHours(open: "07:00", close: "18:00"),
            wed: DayHours(open: "07:00", close: "18:00"),
            thu: DayHours(open: "07:00", close: "18:00"),
            fri: DayHours(open: "07:00", close: "18:00"),
            sat: DayHours(open: "08:00", close: "18:00"),
            sun: nil
        )
    }

    @Test func openDuringHours() {
        // Wednesday Nov 18, 10 am.
        #expect(weekdayHours.isOpen(at: Self.date(day: 18, hour: 10), calendar: Self.detroitCalendar) == true)
    }

    @Test func closedBeforeOpening() {
        // Wednesday Nov 18, 6 am.
        #expect(weekdayHours.isOpen(at: Self.date(day: 18, hour: 6), calendar: Self.detroitCalendar) == false)
    }

    @Test func closedAfterClosing() {
        // Wednesday Nov 18, 7 pm.
        #expect(weekdayHours.isOpen(at: Self.date(day: 18, hour: 19), calendar: Self.detroitCalendar) == false)
    }

    @Test func closedOnClosedDay() {
        // Sunday Nov 22, 10 am. Sunday is nil, so closed.
        #expect(weekdayHours.isOpen(at: Self.date(day: 22, hour: 10), calendar: Self.detroitCalendar) == false)
    }

    @Test func unknownWhenNoHoursAtAll() {
        // No hours recorded for any day: unknown, not a guess.
        #expect(WeeklyHours.empty.isOpen(at: Self.date(day: 18, hour: 10), calendar: Self.detroitCalendar) == nil)
    }

    @Test func overnightSpillCountsAsOpen() {
        let hours = WeeklyHours(
            fri: DayHours(open: "07:00", close: "01:00"),
            sat: DayHours(open: "08:00", close: "18:00")
        )
        // Saturday Nov 21, 12:30 am: Friday's overnight hours still cover it.
        #expect(hours.isOpen(at: Self.date(day: 21, hour: 0, minute: 30), calendar: Self.detroitCalendar) == true)
        // Saturday Nov 21, 2 am: past the overnight close.
        #expect(hours.isOpen(at: Self.date(day: 21, hour: 2), calendar: Self.detroitCalendar) == false)
    }

    @Test func closingTextWhileOpen() {
        #expect(weekdayHours.closingText(at: Self.date(day: 18, hour: 10), calendar: Self.detroitCalendar) == "until 6 pm")
    }

    @Test func noClosingTextWhileClosed() {
        #expect(weekdayHours.closingText(at: Self.date(day: 18, hour: 19), calendar: Self.detroitCalendar) == nil)
    }

    @Test func displayTimeFormats() {
        #expect(DayHours.displayTime("07:00") == "7 am")
        #expect(DayHours.displayTime("18:00") == "6 pm")
        #expect(DayHours.displayTime("12:30") == "12:30 pm")
        #expect(DayHours.displayTime("00:30") == "12:30 am")
    }

    @Test func summaryLinesShowClosedDays() {
        let lines = weekdayHours.summaryLines()
        #expect(lines.count == 7)
        #expect(lines[0].day == "Mon")
        #expect(lines[0].text == "7 am to 6 pm")
        #expect(lines[6].day == "Sun")
        #expect(lines[6].text == "Closed")
    }
}
