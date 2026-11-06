import Foundation
import CryptoKit

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct Credentials: Codable, Sendable {
    public var keyID: String
    public var secret: String
    public init(keyID: String, secret: String) { self.keyID = keyID; self.secret = secret }
    public var valid: Bool { !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !secret.isEmpty }
}

public struct FacePhysClient {
    private let credentials: Credentials
    private let session: URLSession
    private let base = URL(string: "https://www.facephys.com")!
    private static let privateSession = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
    public init(credentials: Credentials, session: URLSession? = nil) {
        self.credentials = credentials; self.session = session ?? Self.privateSession
    }
    public static func signature(secret: String, timestamp: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(timestamp.utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return Data(code).base64EncodedString()
    }
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func submissionKey(digest: String, keyID: String) -> String {
        "facepause-v3-" + Self.digest(Data("\(keyID)|rppg|\(digest)".utf8))
    }
    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard credentials.valid else { throw FaceError.message("请先在设置中保存 FacePhys Key。") }
        var r = URLRequest(url: base.appendingPathComponent(path))
        let timestamp = String(Int(Date().timeIntervalSince1970))
        r.setValue(credentials.keyID, forHTTPHeaderField: "x-key-id")
        r.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        r.setValue(Self.signature(secret: credentials.secret, timestamp: timestamp), forHTTPHeaderField: "x-signature")
        r.timeoutInterval = 180
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }
    private func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FaceError.message("没有收到服务器响应。") }
        guard response.statusCode == 200 else {
            let messages = [401: "Key 验证失败，请检查 Key 和 Secret。", 403: "Key 权限或余额不足，请查看 FacePhys 控制台。", 409: "该视频可能仍在处理，请先查看控制台记录。", 429: "服务繁忙，请稍后再试。"]
            throw FaceError.message(messages[response.statusCode] ?? "FacePhys 返回 HTTP \(response.statusCode)。请查看控制台记录；尚未自动重试。")
        }
        return data
    }
    public func authenticate() async throws {
        let data = try await checked(request("api/agent/auth/test"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["ok"] as? Bool == true else {
            throw FaceError.message("FacePhys 未确认认证成功。")
        }
        guard json["apiVersion"] as? Int == 3 else {
            throw FaceError.message("此 Key 不是 V3 接口版本，请在 FacePhys 控制台确认 Key 的版本。尚未上传视频。")
        }
    }
    public func process(video: URL, confirmed: Bool, responseReceived: @escaping (Data) async -> Void = { _ in }, progress: @escaping (String) async -> Void) async throws -> PhysMeasurement {
        guard confirmed else { throw FaceError.message("上传和扣费尚未确认。") }
        // Stable video digest survives a manual retry, including after restarting the app.
        let bytes = try Data(contentsOf: video, options: .mappedIfSafe)
        guard !bytes.isEmpty, bytes.count <= 200 * 1024 * 1024 else { throw FaceError.message("视频为空或超过 200 MB。") }
        let digest = Self.digest(bytes)
        try Task.checkCancellation()
        await progress("验证 Key…")
        try await authenticate()
        await progress("准备安全上传…")
        let data = try await checked(request("api/v2/video/upload/presign", body: [:]))
        struct Presign: Decodable { let uploadUrl: String; let objectKey: String }
        let signed = try JSONDecoder().decode(Presign.self, from: data)
        // The official SDK normalizes encoded slashes only in the URL path.
        let parts = signed.uploadUrl.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let normalized = String(parts[0]).replacingOccurrences(of: "%2F", with: "/", options: .caseInsensitive)
            + (parts.count > 1 ? "?" + parts[1] : "")
        guard let url = URL(string: normalized), url.scheme == "https", let host = url.host,
              host.hasSuffix(".aliyuncs.com") || host == "www.facephys.com" || host.hasSuffix(".facephys.com") else {
            throw FaceError.message("上传地址不在预期的 HTTPS 存储域名内，已停止。")
        }
        try Task.checkCancellation()
        await progress("上传视频…")
        var upload = URLRequest(url: url)
        upload.httpMethod = "PUT"; upload.timeoutInterval = 120
        upload.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: upload, fromFile: video)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw FaceError.message("视频上传失败，尚未提交分析。")
        }
        try Task.checkCancellation()
        await progress("云端分析中，请稍候…")
        let result = try await checked(request("api/v3/video/process", body: [
            "objectKey": signed.objectKey, "capability": "rppg", "confirmCharge": true,
            "videoSha256": digest, "idempotencyKey": Self.submissionKey(digest: digest, keyID: credentials.keyID)
        ]))
        await responseReceived(result)
        return try PhysMeasurement(data: result)
    }
}
