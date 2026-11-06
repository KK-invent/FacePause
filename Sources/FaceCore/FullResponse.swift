import Foundation
import CoreFoundation

public struct ResultField: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let kind: String
}

public struct ResultGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let fields: [ResultField]
    public init(id: String, title: String, fields: [ResultField]) { self.id = id; self.title = title; self.fields = fields }
}

public enum FullResponse {
    public static func groups(from data: Data) -> [ResultGroup] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var groups: [ResultGroup] = []
        let payload = root["data"] as? [String: Any] ?? [:]
        var remaining = payload
        if var cardiac = remaining.removeValue(forKey: "cardiac") as? [String: Any] {
            let hrv = cardiac.removeValue(forKey: "hrv")
            let series = cardiac.removeValue(forKey: "hr_list")
            if !cardiac.isEmpty || (payload["cardiac"] as? [String: Any])?.isEmpty == true {
                appendGroup(&groups, id: "/data/cardiac", title: "基础生理与信号质量", value: cardiac)
            }
            if let hrv { appendGroup(&groups, id: "/data/cardiac/hrv", title: "全部 HRV 指标", value: hrv) }
            if let series { appendGroup(&groups, id: "/data/cardiac/hr_list", title: "逐点心率数据", value: series) }
        } else if let cardiac = payload["cardiac"] {
            appendGroup(&groups, id: "/data/cardiac", title: "基础生理与信号质量", value: cardiac)
        }
        let named = [("bp", "血压估算"), ("spo2", "血氧估算"), ("psych", "服务商心理相关评分"),
                     ("emotion", "服务商表情与情绪输出"), ("face_au", "面部动作单元"),
                     ("behavior", "行为与眼动输出"), ("appearance", "服务商面部属性输出"),
                     ("liveness", "活体检测"), ("audio", "音频相关输出"), ("billing", "计费信息")]
        for (key, title) in named {
            if let value = remaining.removeValue(forKey: key) {
                appendGroup(&groups, id: "/data/" + pointer(key), title: title, value: value)
            }
        }
        // Every unknown provider field is retained, including arrays, nulls and
        // empty containers. New provider modules need no app update to appear.
        if !remaining.isEmpty { appendGroup(&groups, id: "/data", title: "其他返回数据", value: remaining) }
        if payload.isEmpty, let value = root["data"] {
            appendGroup(&groups, id: "/data", title: "返回数据", value: value)
        }
        var metadata = root; metadata.removeValue(forKey: "data")
        if !metadata.isEmpty { appendGroup(&groups, id: "", title: "响应信息与计费回执", value: metadata) }
        return groups
    }
    public static func fields(_ value: Any, path: String = "") -> [ResultField] {
        if let object = value as? [String: Any] {
            if object.isEmpty { return [field(path, value: "{}", kind: "空对象")] }
            return object.keys.sorted().flatMap { fields(object[$0]!, path: path + "/" + pointer($0)) }
        }
        if let array = value as? [Any] {
            if array.isEmpty { return [field(path, value: "[]", kind: "空数组")] }
            return array.enumerated().flatMap { fields($0.element, path: path + "/" + String($0.offset)) }
        }
        if value is NSNull { return [field(path, value: "null（服务返回空值）", kind: "空值")] }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return [field(path, value: number.boolValue ? "true（是）" : "false（否）", kind: "布尔值")]
            }
            return [field(path, value: number.stringValue, kind: "数值")]
        }
        return [field(path, value: value as? String ?? String(describing: value), kind: "文本")]
    }
    public static func prettyJSON(_ data: Data) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: pretty, encoding: .utf8) else { return String(data: data, encoding: .utf8) ?? "无法解码原始 JSON" }
        return text
    }
    public static func rawText(_ data: Data) -> String {
        // Prefer exact UTF-8 bytes for copy/view: reserialization can round
        // high-precision numbers or alter meaningful escaped string content.
        String(data: data, encoding: .utf8) ?? prettyJSON(data)
    }
    private static func appendGroup(_ groups: inout [ResultGroup], id: String, title: String, value: Any) {
        groups.append(ResultGroup(id: id, title: title, fields: fields(value, path: id)))
    }
    private static func pointer(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
    private static func field(_ path: String, value: String, kind: String) -> ResultField {
        let key = path.split(separator: "/").last.map(String.init) ?? "响应"
        let names = ["hr": "心率", "sqi": "信号质量", "sdnn": "HRV · SDNN", "rmssd": "HRV · RMSSD",
                     "ibi_mean": "平均心跳间隔", "pnn20": "pNN20", "pnn50": "pNN50", "breathing_rate": "呼吸率",
                     "LF": "低频功率 LF", "HF": "高频功率 HF", "LF~1HF": "LF/HF 比值", "TP": "总功率 TP", "VLF": "极低频功率 VLF",
                     "sd1": "SD1", "sd2": "SD2", "sbp": "收缩压估算", "dbp": "舒张压估算", "spo2": "血氧估算",
                     "confidence": "服务商置信度", "dominant": "主导分类", "dominant_confidence": "主导分类置信度",
                     "ms": "压力评分（模型）", "mr": "放松评分（模型）", "mf": "疲劳评分（模型）", "sq": "睡眠质量评分（模型）",
                     "mh": "心理健康评分（模型）", "mb": "心理平衡评分（模型）", "con": "专注评分（模型）", "mab": "记忆评分（模型）",
                     "adp": "适应评分（模型）", "sra": "抗压评分（模型）", "blink_rate": "眨眼率", "perclos": "闭眼时间比例",
                     "gaze_yaw": "水平视线偏移", "gaze_pitch": "垂直视线偏移", "is_live": "服务商活体判定", "liveness_score": "活体评分",
                     "points_deducted": "本次扣除 Token", "remaining_points": "剩余 Token",
                     "tokens_deducted": "本次扣除 Token", "remaining_tokens": "剩余 Token", "video_duration": "视频时长", "processing_time": "处理耗时",
                     "message": "响应消息", "requestId": "请求编号", "request_id": "请求编号", "ts": "时间点"]
        return ResultField(id: path, label: names[key] ?? key.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~"), value: value, kind: kind)
    }
}
