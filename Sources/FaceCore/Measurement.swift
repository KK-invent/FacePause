import Foundation
import CoreFoundation

public struct PhysMeasurement: Codable, Sendable {
    public let date: Date
    public let heartRate: Double?
    public let sqi: Double?
    public let rmssd: Double?
    public let sdnn: Double?
    public let breathingRate: Double?
    public let tokens: Double?
    public let remainingTokens: Double?
    /// Exact successful response bytes; optional for v0.1/v0.2 local records.
    public let originalResponse: Data?

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil, (root["success"] as? Bool) != false,
              let payload = root["data"] as? [String: Any], payload["error"] == nil,
              !["processing", "pending", "queued"].contains((root["status"] as? String ?? "").lowercased()),
              !["processing", "pending", "queued"].contains((payload["status"] as? String ?? "").lowercased()) else {
            throw FaceError.message("服务未返回有效的分析结果。请查看控制台检测记录；不要直接重新提交。")
        }
        originalResponse = data
        let cardiac = payload["cardiac"] as? [String: Any] ?? [:]
        func number(_ value: Any?, range: ClosedRange<Double>) -> Double? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            return d.isFinite && range.contains(d) ? d : nil
        }
        let hrv = cardiac["hrv"] as? [String: Any] ?? [:]
        date = Date()
        heartRate = number(cardiac["hr"], range: 1...300)
        sqi = number(cardiac["sqi"], range: 0...1)
        rmssd = number(hrv["rmssd"], range: 0...2000)
        sdnn = number(hrv["sdnn"], range: 0...2000)
        breathingRate = number(hrv["breathing_rate"], range: 1...80)
        // Current V3 responses use tokens_*; points_* remains as a fallback for older records.
        func billing(_ keys: [String], range: ClosedRange<Double>) -> Double? {
            for key in keys { if let value = number(payload[key] ?? root[key], range: range) { return value } }
            return nil
        }
        tokens = billing(["tokens_deducted", "points_deducted"], range: 0...1e12)
        remainingTokens = billing(["remaining_tokens", "remaining_points"], range: 0...1e15)
    }
    public var fieldGroups: [ResultGroup] { originalResponse.map(FullResponse.groups) ?? [] }
    /// Per-point heart rate returned in data.cardiac.hr_list, in response order; invalid points are skipped.
    public var heartSeries: [Double] {
        guard let originalResponse,
              let root = try? JSONSerialization.jsonObject(with: originalResponse) as? [String: Any],
              let cardiac = (root["data"] as? [String: Any])?["cardiac"] as? [String: Any],
              let list = cardiac["hr_list"] as? [[String: Any]] else { return [] }
        return list.compactMap { point in
            guard let n = point["hr"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            return d.isFinite && (1...300).contains(d) ? d : nil
        }
    }

    // A conservative product gate, not a clinical confidence threshold.
    public var suitableForAdvice: Bool { (sqi ?? -1) >= 0.65 && heartRate != nil }
    public var qualityTitle: String {
        guard let sqi else { return "质量未知 · 建议复测" }
        return sqi >= 0.65 ? "信号较清晰" : "信号偏弱 · 建议复测"
    }
    public var advice: [String] {
        guard suitableForAdvice else {
            return ["本次信号质量不足或缺失，先不解读身体状态。", "让光线均匀照在脸上，保持正面、安静不说话，再采集一次。"]
        }
        var tips = ["本次数据可留作个人参考；比较趋势时，尽量选择相同时间、坐姿和光线。"]
        if let hr = heartRate, hr < 60 || hr > 100 {
            tips.append("心率估算在常见成人静息范围之外。先安静休息，再用手表或其他可靠设备核对；这一次结果不能判断健康状况。")
        } else {
            tips.append("这段测量结束了，可以把视线移开屏幕，放松肩颈，按自己的感受安排休息。")
        }
        if rmssd != nil || sdnn != nil {
            tips.append("HRV 是心跳间隔的变化。30 秒数据只适合谨慎参考，不用单次高低判断压力、疲劳或睡眠质量。")
        }
        return tips
    }
    public static func sample() -> PhysMeasurement {
        try! PhysMeasurement(data: DemoResponse.data)
    }
}

public enum FaceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
