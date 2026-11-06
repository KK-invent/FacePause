import Foundation
import FaceCore
#if !FACEPAUSE_STANDALONE_TEST
import XCTest
#endif

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private func date(_ day: Int = 31, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func testIntervalAndActiveHours() {
        let p = SchedulePolicy()
        XCTAssertEqual(p.nextDate(after: date(31, 10), calendar: calendar), date(31, 11))
        XCTAssertEqual(p.nextDate(after: date(31, 6), calendar: calendar), date(31, 9))
        XCTAssertTrue(p.isWithinHours(date(31, 9), calendar: calendar))
        XCTAssertFalse(p.isWithinHours(date(31, 22), calendar: calendar))
    }
    func testNightAndQuotaMoveToNextDay() {
        let p = SchedulePolicy()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date(31, 9))!
        XCTAssertEqual(p.nextDate(after: date(31, 21, 30), calendar: calendar), tomorrow)
        XCTAssertEqual(p.nextDate(after: date(31, 10), quotaExhausted: true, calendar: calendar), tomorrow)
    }
    func testBlockedStatesCannotStart() {
        let p = SchedulePolicy()
        XCTAssertTrue(p.mayStart(now: date(31, 10), enabled: true, available: true, busy: false, pending: false, usedToday: 0, calendar: calendar))
        for flags in [(false, true, false, false), (true, false, false, false), (true, true, true, false), (true, true, false, true)] {
            XCTAssertFalse(p.mayStart(now: date(31, 10), enabled: flags.0, available: flags.1, busy: flags.2, pending: flags.3, usedToday: 0, calendar: calendar))
        }
        XCTAssertFalse(p.mayStart(now: date(31, 10), enabled: true, available: true, busy: false, pending: false, usedToday: 6, calendar: calendar))
        XCTAssertFalse(p.mayStart(now: date(31, 23), enabled: true, available: true, busy: false, pending: false, usedToday: 0, calendar: calendar))
    }
    func testReservationsSurviveRestartAndStopAtLimit() throws {
        var usage = DailyUsage(day: date(31, 10))
        for _ in 0..<6 { XCTAssertTrue(usage.reserve(on: date(31, 11), limit: 6, calendar: calendar)) }
        var restored = try JSONDecoder().decode(DailyUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertFalse(restored.reserve(on: date(31, 12), limit: 6, calendar: calendar))
        XCTAssertEqual(restored.used(on: date(31, 12), calendar: calendar), 6)
    }
    func testMidnightResetsQuota() {
        var usage = DailyUsage(day: date(30, 10), count: 6)
        XCTAssertEqual(usage.used(on: date(31, 0), calendar: calendar), 0)
        XCTAssertTrue(usage.reserve(on: date(31, 9), limit: 6, calendar: calendar))
        XCTAssertEqual(usage.used(on: date(31, 9), calendar: calendar), 1)
    }
    func testLateWakeSchedulesFutureWithoutCatchUp() {
        let p = SchedulePolicy()
        XCTAssertEqual(p.nextDate(after: date(31, 17, 47), calendar: calendar), date(31, 18, 47))
    }
}
