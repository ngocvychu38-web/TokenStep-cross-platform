import Foundation

/// The wall ends with the current Shanghai week, including blank future days.
enum ContributionWallCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    static func start(endingAt date: Date, weeks: Int) -> Date {
        let calendar = calendar
        let today = calendar.startOfDay(for: date)
        let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -mondayOffset, to: today)!
        return calendar.date(byAdding: .day, value: -7 * (max(1, weeks) - 1), to: currentMonday)!
    }
}
