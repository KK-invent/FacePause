import SwiftUI
import Combine
import FaceCore

enum MeasurementPhase: Equatable {
    case idle, countdown, starting, recording, preparing, awaitingApproval, analyzing, complete, failed
}

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    let camera = CameraService()
    let preferences: Preferences
    let deepSeek: DeepSeekStore
    private let sessionMonitor = SessionMonitor()
    let uiTest = ProcessInfo.processInfo.arguments.contains("--ui-test")
    @Published var phase: MeasurementPhase = .idle { didSet { onPanelUpdate?() } }
    @Published var video: URL?
    @Published var result: PhysMeasurement?
    @Published var isSample = false
    @Published var status = "菜单栏待机"
    @Published var error: String?
    @Published var credentialState = "未配置"
    @Published var canAnalyze = false
    @Published var countdown = 5
    @Published var nextDetection: Date?
    @Published var showChargeSheet = false
    var onPanelUpdate: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHidePanel: (() -> Void)?
    private var didStart = false
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var cancellations = Set<AnyCancellable>()
    private var cancelled = false
    private var lastAutomatic = false
    var busy: Bool { phase == .analyzing }
    var processingVideo: Bool { [.countdown, .starting, .recording, .preparing].contains(phase) }
    var active: Bool { busy || processingVideo || deepSeek.isAnalyzing }
    var pending: Bool { video != nil && result == nil }
    var scheduleSummary: String {
        if !preferences.enabled { return "定时检测已暂停" }
        if preferences.automaticUpload && !canAnalyze { return "等待连接 FacePhys" }
        if pending { return "等待处理本次视频" }
        if let nextDetection { return "下次 " + nextDetection.formatted(date: .omitted, time: .shortened) }
        return "定时检测待机"
    }

    init() {
        preferences = Preferences(testing: ProcessInfo.processInfo.arguments.contains("--ui-test"))
        deepSeek = DeepSeekStore(testing: ProcessInfo.processInfo.arguments.contains("--ui-test"))
        deepSeek.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellations)
        camera.onFinished = { [weak self] outcome in self?.captureFinished(outcome) }
        camera.$recording.dropFirst().receive(on: RunLoop.main).sink { [weak self] recording in
            guard let self else { return }
            if !recording && self.phase == .recording { self.phase = .preparing; self.status = "正在整理本地视频" }
        }.store(in: &cancellations)
        preferences.onChange = { [weak self] in
            guard let self else { return }
            if !self.preferences.enabled && self.lastAutomatic && self.processingVideo { self.cancelCapture() }
            self.reschedule()
            self.objectWillChange.send()
        }
        sessionMonitor.onUnavailable = { [weak self] in
            guard let self else { return }
            if self.processingVideo { self.cancelCapture() }
            self.deepSeek.cancel()
            KeychainStore.clearMemoryCache()
            self.onHidePanel?()
        }
        sessionMonitor.onResume = { [weak self] in
            guard let self else { return }
            if !self.uiTest { self.refreshCredentials(); self.deepSeek.refreshCredentials() }
            self.reschedule()
        }
    }
    func start() async {
        guard !didStart else { return }; didStart = true
        if !uiTest {
            refreshCredentials()
            deepSeek.refreshCredentials()
            if let (saved, localVideo) = LocalFiles.latestResult() {
                result = saved; video = localVideo; status = "上次检测结果 · " + saved.date.formatted(date: .omitted, time: .shortened)
                deepSeek.setMeasurement(saved, video: localVideo)
            }
        }
        reschedule()
        if !uiTest {
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--sample") { showSample() }
    }
    func refreshCredentials() {
        do {
            canAnalyze = try KeychainStore.load()?.valid == true
            credentialState = canAnalyze ? "已保存" : "未配置"
            if canAnalyze { error = nil }
            if !canAnalyze { status = "先在设置中连接 FacePhys" }
        } catch { self.error = error.localizedDescription; canAnalyze = false; credentialState = "钥匙串待授权" }
        reschedule()
    }
    func reschedule() {
        preferences.refreshDay()
        nextDetection = preferences.enabled ? preferences.policy.nextDate(after: Date(), quotaExhausted: preferences.usedToday >= preferences.dailyLimit) : nil
    }
    func tick(now: Date = Date()) {
        preferences.refreshDay()
        guard let due = nextDetection, now >= due else { return }
        reschedule() // missed ticks are skipped, never replayed in a burst
        guard preferences.policy.mayStart(now: now, enabled: preferences.enabled, available: sessionMonitor.available,
                                          busy: active, pending: pending, usedToday: preferences.usedToday) else { return }
        guard !preferences.automaticUpload || canAnalyze else { status = "等待连接 FacePhys"; return }
        beginCapture(automatic: true)
    }
    func beginCapture(automatic: Bool = false) {
        guard !active, !pending else { return }
        guard sessionMonitor.available else { status = "锁屏或睡眠时不检测"; return }
        preferences.refreshDay()
        if preferences.automaticUpload && preferences.usedToday >= preferences.dailyLimit {
            fail("今日已达到 \(preferences.dailyLimit) 次上限，可在设置中调整。"); return
        }
        lastAutomatic = automatic; cancelled = false
        deepSeek.setMeasurement(nil, video: nil)
        video = nil; result = nil; isSample = false; error = nil; countdown = 5
        status = "即将检测，请正对摄像头"; phase = .countdown
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                for value in stride(from: 5, through: 1, by: -1) {
                    try Task.checkCancellation()
                    self.countdown = value
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                self.phase = .starting; self.status = "正在检查面部是否入镜"
                guard await self.camera.start() else {
                    if self.cancelled { self.finishCancellation() } else { self.fail(self.camera.message) }
                    return
                }
                try Task.checkCancellation()
                var found = false
                for _ in 0..<12 {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    if self.camera.facePresent { found = true; break }
                }
                guard found else { self.camera.stop(); self.fail("未检测到清晰的单人面部，本次跳过，不上传。请保持正面和均匀光线。"); return }
                try Task.checkCancellation()
                guard self.sessionMonitor.available else { throw CancellationError() }
                self.status = "安静采集，不显示摄像头画面"
                self.phase = .recording
                self.camera.record()
            } catch { self.camera.stop(discard: true); self.finishCancellation() }
        }
    }
    func cancelCapture() {
        guard processingVideo else { return }
        cancelled = true; captureTask?.cancel(); camera.stop(discard: true)
        status = "正在取消…"
    }
    private func finishCancellation() {
        status = "本次已取消，未上传"; phase = .idle; reschedule()
        onHidePanel?()
    }
    private func captureFinished(_ outcome: Result<URL, Error>) {
        if cancelled { finishCancellation(); return }
        switch outcome {
        case let .success(url):
            video = url; status = "摄像头已关闭"; phase = .awaitingApproval
            if preferences.automaticUpload && canAnalyze && !uiTest && sessionMonitor.available {
                analysisTask = Task { [weak self] in await self?.analyze() }
            } else if uiTest { status = "本地测试完成 · 不上传、不扣费" }
            else if !canAnalyze { status = "采集完成，请先连接 FacePhys" }
            else { status = "采集完成，等待上传确认" }
        case let .failure(error):
            if error is CancellationError { finishCancellation() }
            else { fail(error.localizedDescription) }
        }
    }
    func requestAnalysis() {
        guard pending, !active else { return }
        if !canAnalyze { onOpenSettings?(); return }
        showChargeSheet = true; onOpenDashboard?()
    }
    func analyze() async {
        guard let video, !active else { return }
        guard !uiTest else { status = "测试模式禁止上传与扣费"; return }
        guard sessionMonitor.available else { status = "当前会话不可用，暂不上传"; return }
        error = nil; result = nil; isSample = false
        do {
            guard let credentials = try KeychainStore.load() else { throw FaceError.message("请先填写 FacePhys Key。") }
            guard preferences.reserveSubmission() else { throw FaceError.message("已达到今日分析次数上限。") }
            status = "正在提交分析"; phase = .analyzing
            let measured = try await FacePhysClient(credentials: credentials).process(video: video, confirmed: true, responseReceived: { [weak self] data in
                do { try LocalFiles.saveResponse(data, beside: video) }
                catch { await MainActor.run { self?.error = "完整响应保存失败，请检查磁盘空间。" } }
            }) { [weak self] message in
                await MainActor.run { self?.status = message }
            }
            result = measured; status = measured.qualityTitle; phase = .complete
            do { try LocalFiles.save(measured, beside: video) }
            catch { self.error = "结果已显示，但保存失败，请检查磁盘空间。" }
            deepSeek.setMeasurement(measured, video: video)
            reschedule()
        } catch {
            if preferences.enabled { preferences.enabled = false }
            fail("\(error is URLError ? "网络请求未完成。" : error.localizedDescription) 定时检测已暂停，请查看控制台记录确认扣费，再恢复。应用不会自动重试。")
        }
    }
    func clearMeasurement() {
        guard !active else { return }
        video = nil; result = nil; error = nil; isSample = false
        deepSeek.setMeasurement(nil, video: nil)
        status = "菜单栏待机"; phase = .idle; reschedule(); onHidePanel?()
    }
    func fail(_ text: String) {
        error = text; status = text; phase = .failed
        reschedule()
    }
    func showSample() {
        guard !active else { return }
        video = nil; result = .sample(); isSample = true
        deepSeek.setMeasurement(result, video: nil, sample: true)
        status = "示例结果 · 没有实际检测"; phase = .complete
    }
    func previewIsland() {
        guard !active else { return }; showSample(); onPanelUpdate?()
    }
    func prepareToQuit() { captureTask?.cancel(); deepSeek.cancel(); camera.stop(discard: true) }
}
