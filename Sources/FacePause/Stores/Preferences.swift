import Foundation
import Combine
import FaceCore

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var enabled: Bool { didSet { save() } }
    @Published var automaticUpload: Bool { didSet { save() } }
    @Published var interval: Int { didSet { save() } }
    @Published var dailyLimit: Int { didSet { save() } }
    @Published var startHour: Int { didSet { save() } }
    @Published var endHour: Int { didSet { save() } }
    @Published private(set) var usedToday: Int = 0
    private var usage: DailyUsage

    init(testing: Bool = false) {
        defaults = testing ? UserDefaults(suiteName: "local.facepause.ui-test")! : .standard
        // Initial v0.2 configuration was explicitly authorized by the user:
        // hourly automatic paid analysis with a daily limit. Later edits persist.
        defaults.register(defaults: ["schedule.enabled": true, "schedule.autoUpload": true,
                                    "schedule.interval": 60, "schedule.dailyLimit": 6,
                                    "schedule.startHour": 9, "schedule.endHour": 22])
        enabled = defaults.bool(forKey: "schedule.enabled")
        automaticUpload = defaults.bool(forKey: "schedule.autoUpload")
        interval = max(15, defaults.integer(forKey: "schedule.interval"))
        dailyLimit = min(24, max(1, defaults.integer(forKey: "schedule.dailyLimit")))
        let initialStart = min(23, max(0, defaults.integer(forKey: "schedule.startHour")))
        startHour = initialStart
        endHour = min(24, max(initialStart + 1, defaults.integer(forKey: "schedule.endHour")))
        if let data = defaults.data(forKey: "schedule.usage"), let saved = try? JSONDecoder().decode(DailyUsage.self, from: data) {
            usage = saved
        } else { usage = DailyUsage(day: Date()) }
        usedToday = usage.used(on: Date())
    }
    var policy: SchedulePolicy { SchedulePolicy(intervalMinutes: interval, startHour: startHour, endHour: endHour, dailyLimit: dailyLimit) }
    func refreshDay() { usedToday = usage.used(on: Date()) }
    func reserveSubmission() -> Bool {
        guard usage.reserve(on: Date(), limit: dailyLimit) else { return false }
        defaults.set(try? JSONEncoder().encode(usage), forKey: "schedule.usage")
        refreshDay()
        return true
    }
    private func save() {
        defaults.set(enabled, forKey: "schedule.enabled")
        defaults.set(automaticUpload, forKey: "schedule.autoUpload")
        defaults.set(interval, forKey: "schedule.interval")
        defaults.set(dailyLimit, forKey: "schedule.dailyLimit")
        defaults.set(startHour, forKey: "schedule.startHour")
        defaults.set(endHour, forKey: "schedule.endHour")
        onChange?()
    }
}
