import Foundation

public struct SchedulePolicy: Sendable {
    public var intervalMinutes: Int
    public var startHour: Int
    public var endHour: Int
    public var dailyLimit: Int
    public init(intervalMinutes: Int = 60, startHour: Int = 9, endHour: Int = 22, dailyLimit: Int = 6) {
        self.intervalMinutes = max(15, intervalMinutes)
        self.startHour = min(23, max(0, startHour))
        self.endHour = min(24, max(self.startHour + 1, endHour))
        self.dailyLimit = max(1, min(24, dailyLimit))
    }
    public func isWithinHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour && hour < endHour
    }
    public func nextDate(after date: Date, quotaExhausted: Bool = false, calendar: Calendar = .current) -> Date {
        let candidate = date.addingTimeInterval(Double(intervalMinutes) * 60)
        let today = calendar.startOfDay(for: date)
        if quotaExhausted {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            return calendar.date(byAdding: .hour, value: startHour, to: tomorrow)!
        }
        if isWithinHours(candidate, calendar: calendar) { return candidate }
        let candidateDay = calendar.startOfDay(for: candidate)
        if calendar.component(.hour, from: candidate) < startHour {
            return calendar.date(byAdding: .hour, value: startHour, to: candidateDay)!
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: candidateDay)!
        return calendar.date(byAdding: .hour, value: startHour, to: nextDay)!
    }
    public func mayStart(now: Date, enabled: Bool, available: Bool, busy: Bool, pending: Bool,
                         usedToday: Int, calendar: Calendar = .current) -> Bool {
        enabled && available && !busy && !pending && usedToday < dailyLimit && isWithinHours(now, calendar: calendar)
    }
}

public struct DailyUsage: Codable, Sendable {
    public private(set) var day: Date
    public private(set) var count: Int
    public init(day: Date, count: Int = 0) { self.day = day; self.count = max(0, count) }
    public func used(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(day, inSameDayAs: date) ? count : 0
    }
    public mutating func reserve(on date: Date, limit: Int, calendar: Calendar = .current) -> Bool {
        let used = used(on: date, calendar: calendar)
        guard used < limit else { return false }
        day = calendar.startOfDay(for: date); count = used + 1
        return true
    }
}
