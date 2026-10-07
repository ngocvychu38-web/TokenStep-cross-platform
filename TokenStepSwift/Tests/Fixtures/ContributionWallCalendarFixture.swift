import Foundation

@main struct ContributionWallCalendarFixture {
    static func main() {
        let formatter = ISO8601DateFormatter()
        // Exercise every weekday, the month/year boundary, and the Shanghai midnight boundary.
        for timestamp in ["2026-10-05T04:00:00Z", "2026-10-06T04:00:00Z", "2026-10-07T04:00:00Z", "2026-10-08T04:00:00Z", "2026-10-09T04:00:00Z", "2026-10-10T04:00:00Z", "2026-10-11T04:00:00Z", "2026-01-01T04:00:00Z", "2026-10-06T16:00:00Z"] {
            let date = formatter.date(from: timestamp)!
            let calendar = ContributionWallCalendar.calendar
            let today = calendar.startOfDay(for: date)
            let start = ContributionWallCalendar.start(endingAt: date, weeks: 34)
            let offset = calendar.dateComponents([.day], from: start, to: today).day!
            precondition((231...237).contains(offset)) // Today is always in the last column.
            precondition(calendar.component(.weekday, from: start) == 2)
            precondition(offset % 7 == (calendar.component(.weekday, from: today) + 5) % 7)
        }
        let today = formatter.date(from: "2026-10-07T04:00:00Z")!
        let start = ContributionWallCalendar.start(endingAt: today, weeks: 34)
        let calendar = ContributionWallCalendar.calendar
        precondition(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: today)).day == 233)
        precondition(calendar.dateComponents([.day], from: start, to: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))!).day == 232)
        print("contribution_wall_calendar_ok: weekdays, today/yesterday, year boundary, Shanghai midnight")
    }
}
