#if DEBUG
import Foundation

/// Developer sample shops. They exist so the UI can be exercised in a debug
/// build when the real directory is empty, and for nothing else:
/// - This file is compiled out of release builds entirely (`#if DEBUG`),
///   so sample shops can never appear in a TestFlight build.
/// - Every sample shop is flagged `isSample` and labeled "Sample data" in
///   the UI, so it is never mistaken for a real shop.
/// - Sample shops are excluded from check ins, region monitoring, and the
///   Supabase directory mapping by every caller that touches them.
enum SampleData {
    static func makeShops() -> [Shop] {
        [
            Shop(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Sample Shop One",
                address: "1 Sample Street, Detroit, MI",
                neighborhood: "Midtown",
                latitude: 42.3487,
                longitude: -83.0567,
                kind: .independent,
                hours: WeeklyHours(
                    mon: DayHours(open: "07:00", close: "18:00"),
                    tue: DayHours(open: "07:00", close: "18:00"),
                    wed: DayHours(open: "07:00", close: "18:00"),
                    thu: DayHours(open: "07:00", close: "18:00"),
                    fri: DayHours(open: "07:00", close: "18:00"),
                    sat: DayHours(open: "08:00", close: "18:00"),
                    sun: DayHours(open: "08:00", close: "16:00")
                ),
                tags: ["Sample"],
                source: "Developer sample data, not a real shop",
                lastVerifiedDate: Date(),
                isSample: true
            ),
            Shop(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Sample Shop Two",
                address: "2 Sample Street, Detroit, MI",
                neighborhood: "Corktown",
                latitude: 42.3298,
                longitude: -83.0608,
                kind: .chain,
                hours: WeeklyHours(
                    mon: DayHours(open: "06:00", close: "20:00"),
                    tue: DayHours(open: "06:00", close: "20:00"),
                    wed: DayHours(open: "06:00", close: "20:00"),
                    thu: DayHours(open: "06:00", close: "20:00"),
                    fri: DayHours(open: "06:00", close: "20:00"),
                    sat: DayHours(open: "07:00", close: "20:00"),
                    sun: DayHours(open: "07:00", close: "18:00")
                ),
                tags: ["Sample"],
                source: "Developer sample data, not a real shop",
                lastVerifiedDate: Date(),
                isSample: true
            ),
        ]
    }
}
#endif
