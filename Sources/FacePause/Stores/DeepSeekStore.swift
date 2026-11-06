import Foundation
import Combine
import FaceCore

@MainActor final class DeepSeekStore: ObservableObject {
    @Published private(set) var report: DeepSeekReport?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var canAnalyze = false
    @Published private(set) var credentialState = "未配置"
    @Published var error: String?
    @Published private(set) var unavailableReason: String?
    private var input: DeepSeekInput?
    private var video: URL?
    private var operation = UUID()
    private var task: Task<Void, Never>?
    private let testing: Bool

    init(testing: Bool) { self.testing = testing }

    func refreshCredentials() {
        guard !testing else { return }
        do {
            canAnalyze = try KeychainStore.loadDeepSeek() != nil
            credentialState = canAnalyze ? "已保存" : "未配置"
        } catch {
            canAnalyze = false; credentialState = "钥匙串待授权"
        }
    }

    func setMeasurement(_ measurement: PhysMeasurement?, video: URL?, sample: Bool = false) {
        cancel()
        input = nil; self.video = video; report = nil; error = nil; unavailableReason = nil
        guard let measurement else { return }
        guard !testing, !sample else {
            unavailableReason = "示例和本地验收模式不调用 DeepSeek，也不扣费。"
            return
        }
        do {
            let prepared = try DeepSeekInput(measurement: measurement)
            input = prepared
            if let video { report = LocalFiles.deepSeekReport(beside: video, matching: prepared) }
        } catch { unavailableReason = error.localizedDescription }
    }

    func generate() {
        guard !testing, !isAnalyzing, let input, unavailableReason == nil else { return }
        error = nil
        let key: String
        do {
            guard let saved = try KeychainStore.loadDeepSeek() else {
                throw FaceError.message("请先到设置连接 DeepSeek。")
            }
            key = saved
        } catch { self.error = error.localizedDescription; refreshCredentials(); return }
        let currentOperation = UUID()
        operation = currentOperation
        let destination = video
        isAnalyzing = true
        task = Task { [weak self] in
            do {
                let generated = try await DeepSeekClient(apiKey: key).analyze(input)
                try Task.checkCancellation()
                guard let self, self.operation == currentOperation else { return }
                self.report = generated
                if let destination {
                    do { try LocalFiles.saveDeepSeek(generated, beside: destination) }
                    catch { self.error = "解读已生成，但本地保存失败；请先复制解读并检查磁盘空间。" }
                } else { self.error = "解读已生成，但没有可用的本地记录目录；请先复制解读。" }
                self.isAnalyzing = false; self.task = nil
            } catch {
                guard let self, self.operation == currentOperation else { return }
                self.isAnalyzing = false; self.task = nil
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                self.error = error is URLError
                    ? "DeepSeek 网络请求未完成，未自动重试；服务端可能已计费，请先核对调用记录。"
                    : error.localizedDescription
            }
        }
    }

    func cancel() {
        operation = UUID()
        task?.cancel(); task = nil; isAnalyzing = false
    }
}
