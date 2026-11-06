import Foundation

public struct ProviderReport: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let fields: [ResultField]
}

public enum ProviderReports {
    public static func extract(from data: Data) -> [ProviderReport] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return collect(root, path: "", key: "")
    }
    private static func collect(_ value: Any, path: String, key: String) -> [ProviderReport] {
        if isReportKey(key), hasText(value) {
            return [ProviderReport(id: path, title: title(for: key), fields: FullResponse.fields(value, path: path))]
        }
        if let object = value as? [String: Any] {
            return object.keys.sorted().flatMap { child in
                collect(object[child]!, path: path + "/" + escape(child), key: child)
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap { collect($0.element, path: path + "/" + String($0.offset), key: "") }
        }
        return []
    }
    private static func isReportKey(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        let terms = ["analysis", "diagnosis", "diagnoses", "diagnostic", "report", "summary", "recommendation", "suggestion",
                     "advice", "conclusion", "interpretation", "assessment", "evaluation", "llm", "诊断", "分析", "报告", "建议", "总结", "结论", "解读", "评估"]
        // Descriptive metadata is not a returned analysis report.
        guard !["version", "status", "model", "time", "duration", "id"].contains(where: { normalized.hasSuffix("_" + $0) }) else { return false }
        return terms.contains(where: normalized.contains)
    }
    private static func hasText(_ value: Any) -> Bool {
        if let text = value as? String { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let object = value as? [String: Any] { return object.values.contains(where: hasText) }
        if let array = value as? [Any] { return array.contains(where: hasText) }
        return false
    }
    private static func title(for key: String) -> String {
        let k = key.lowercased()
        if k.contains("diagnos") || k.contains("诊断") { return "服务返回的诊断文字" }
        if k.contains("advice") || k.contains("recommend") || k.contains("suggest") || k.contains("建议") { return "服务返回的建议" }
        if k.contains("summary") || k.contains("总结") || k.contains("conclusion") { return "服务返回的总结" }
        return "服务返回的分析报告"
    }
    private static func escape(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
}
