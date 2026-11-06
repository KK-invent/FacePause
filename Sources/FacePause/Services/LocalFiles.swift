import Foundation
import FaceCore

enum LocalFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FacePause/Sessions", isDirectory: true)
    }
    static func newSession() throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        return directory
    }
    static func save(_ result: PhysMeasurement, beside video: URL) throws {
        let data = try JSONEncoder().encode(result)
        let file = video.deletingLastPathComponent().appendingPathComponent("result.json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        if let original = result.originalResponse { try saveResponse(original, beside: video) }
    }
    static func saveResponse(_ data: Data, beside video: URL) throws {
        let file = video.deletingLastPathComponent().appendingPathComponent("response.json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func saveDeepSeek(_ report: DeepSeekReport, beside video: URL) throws {
        let file = video.deletingLastPathComponent().appendingPathComponent("deepseek-analysis.json")
        try JSONEncoder().encode(report).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func deepSeekReport(beside video: URL, matching input: DeepSeekInput) -> DeepSeekReport? {
        let file = video.deletingLastPathComponent().appendingPathComponent("deepseek-analysis.json")
        guard let data = try? Data(contentsOf: file),
              let report = try? JSONDecoder().decode(DeepSeekReport.self, from: data),
              report.matches(input) else { return nil }
        return report
    }
    static func latestResult() -> (PhysMeasurement, URL)? {
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let files = directories.map { $0.appendingPathComponent("result.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return first > second
            }
        for file in files {
            if let data = try? Data(contentsOf: file), let result = try? JSONDecoder().decode(PhysMeasurement.self, from: data) {
                return (result, file.deletingLastPathComponent().appendingPathComponent("measurement.mp4"))
            }
        }
        return nil
    }
}
