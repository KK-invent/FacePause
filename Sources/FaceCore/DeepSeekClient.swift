import Foundation

private final class DeepSeekNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct DeepSeekClient {
    public static let model = "deepseek-flash"
    private let apiKey: String
    private let session: URLSession
    private static let privateSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: DeepSeekNoRedirect(), delegateQueue: nil)
    }()
    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey; self.session = session ?? Self.privateSession
    }
    private func request(_ path: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FaceError.message("请先在设置中保存 DeepSeek API Key。")
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/" + path)!)
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        return request
    }
    private func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FaceError.message("DeepSeek 没有返回有效响应。") }
        guard response.statusCode == 200 else {
            let messages = [
                400: "DeepSeek 拒绝了请求参数，请检查模型和接口配置。",
                401: "DeepSeek API Key 无效，请在设置中重新保存。",
                402: "DeepSeek 账户余额不足，请在官方控制台充值。",
                403: "DeepSeek 拒绝访问，请核对 Key 权限。",
                404: "DeepSeek 模型或接口不可用；未切换到其他模型。",
                422: "DeepSeek 无法处理本次参数。",
                429: "DeepSeek 请求限流，请稍后手动再试。",
                500: "DeepSeek 服务暂时出错，请稍后手动再试。",
                503: "DeepSeek 服务繁忙，请稍后手动再试。"
            ]
            // Upstream error bodies can echo credentials or private input.
            throw FaceError.message(messages[response.statusCode] ?? "DeepSeek 返回 HTTP \(response.statusCode)。未自动重试。")
        }
        return data
    }
    public func authenticate() async throws {
        struct Models: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let data = try await checked(request("models"))
        guard let models = try? JSONDecoder().decode(Models.self, from: data),
              models.data.contains(where: { $0.id == Self.model }) else {
            throw FaceError.message("Key 已连接，但账户未返回 deepseek-flash；未改用其他模型。")
        }
    }
    public func analyze(_ input: DeepSeekInput) async throws -> DeepSeekReport {
        try Task.checkCancellation()
        var request = try request("chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model, "stream": false, "thinking": ["type": "disabled"],
            "temperature": 0.2, "max_tokens": 2800, "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": DeepSeekPrompt.system],
                ["role": "user", "content": "请解读以下单次检测数据并返回约定的 JSON：\n" + input.json]
            ]
        ])
        let data = try await checked(request)
        try Task.checkCancellation()
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let finish_reason: String
                let message: Message
            }
            let model: String
            let choices: [Choice]
            let usage: DeepSeekReport.Usage?
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let choice = completion.choices.first else {
            throw FaceError.message("DeepSeek 返回格式不完整，未自动重试；本次可能已产生文本费用。")
        }
        guard choice.finish_reason == "stop" else {
            throw FaceError.message("DeepSeek 解读未完整生成（可能达到输出上限或被过滤），未自动重试；请先核对调用记录。")
        }
        guard let text = choice.message.content,
              let content = try? JSONDecoder().decode(DeepSeekContent.self, from: Data(text.utf8)),
              content.valid else {
            throw FaceError.message("DeepSeek 没有返回可展示的完整解读，未自动重试；本次可能已产生文本费用。")
        }
        return DeepSeekReport(sourceDigest: input.sourceDigest, servedModel: completion.model,
                              content: content, usage: completion.usage)
    }
}
