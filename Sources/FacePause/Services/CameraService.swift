import AVFoundation
import Combine
import Foundation
import Vision
import FaceCore

final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let frames = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "local.facepause.camera")
    private let faceQueue = DispatchQueue(label: "local.facepause.face-check", qos: .utility)
    private var configured = false
    private var starting = false
    private var lastFaceCheck = Date.distantPast
    private var checkingRecording = false
    private var checkedFrames = 0
    private var usableFrames = 0
    private var discarded = false
    @Published private(set) var ready = false
    @Published private(set) var recording = false
    @Published private(set) var elapsed = 0
    @Published private(set) var facePresent = false
    @Published var message = "摄像头待机"
    @Published private(set) var permissionState = AVCaptureDevice.authorizationStatus(for: .video)
    private var timer: Timer?
    private var startedAt: Date?
    var onFinished: ((Result<URL, Error>) -> Void)?

    @MainActor func start() async -> Bool {
        if ready { return true }
        guard !starting else { return false }
        starting = true
        defer { starting = false }
        facePresent = false
        guard await authorizeCamera() else {
            message = "摄像头未授权，请在系统设置 → 隐私与安全性 → 摄像头中允许片刻。"
            return false
        }
        if Task.isCancelled { return false }
        let failure: String? = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    if !self.configured {
                        self.session.beginConfiguration()
                        defer { self.session.commitConfiguration() }
                        self.session.sessionPreset = .hd1280x720
                        guard let device = AVCaptureDevice.default(for: .video) else { throw FaceError.message("未找到摄像头。") }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input), self.session.canAddOutput(self.output), self.session.canAddOutput(self.frames) else {
                            throw FaceError.message("摄像头暂时不可用，请关闭其他占用摄像头的应用。")
                        }
                        self.session.addInput(input)
                        self.session.addOutput(self.output)
                        self.frames.alwaysDiscardsLateVideoFrames = true
                        self.frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        self.frames.setSampleBufferDelegate(self, queue: self.faceQueue)
                        self.session.addOutput(self.frames)
                        self.output.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
                        self.output.maxRecordedFileSize = 180 * 1024 * 1024
                        self.configured = true
                    }
                    self.session.startRunning()
                    continuation.resume(returning: self.session.isRunning ? nil : "摄像头未能启动。")
                } catch { continuation.resume(returning: error.localizedDescription) }
            }
        }
        ready = failure == nil
        message = failure ?? "请保持正面，光线均匀"
        return ready
    }
    @MainActor func authorizeCamera() async -> Bool {
        permissionState = AVCaptureDevice.authorizationStatus(for: .video)
        switch permissionState {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = AVCaptureDevice.authorizationStatus(for: .video)
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    @MainActor func record() {
        guard ready, !recording else { return }
        do {
            let file = try LocalFiles.newSession().appendingPathComponent("capture.mov")
            discarded = false; recording = true; elapsed = 0
            faceQueue.async { self.checkedFrames = 0; self.usableFrames = 0; self.checkingRecording = true }
            queue.async { self.output.startRecording(to: file, recordingDelegate: self) }
        } catch { onFinished?(.failure(error)) }
    }
    @MainActor func stop(discard: Bool = false) {
        if discard { discarded = true }
        ready = false
        queue.async {
            if self.output.isRecording { self.output.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
        if !recording { message = "摄像头已关闭" }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastFaceCheck) >= 0.6, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFaceCheck = Date()
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let faces = request.results ?? []
            let box = faces.first?.boundingBox ?? .zero
            let usable = faces.count == 1 && box.width * box.height >= 0.025 && box.midX > 0.15 && box.midX < 0.85
            if checkingRecording { checkedFrames += 1; if usable { usableFrames += 1 } }
            DispatchQueue.main.async { if self.facePresent != usable { self.facePresent = usable } }
        } catch {
            if checkingRecording { checkedFrames += 1 }
            DispatchQueue.main.async { self.facePresent = false }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { [self] in
            self.startedAt = Date()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = min(30, Int(Date().timeIntervalSince(start)))
            }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        let quality: Bool = faceQueue.sync {
            self.checkingRecording = false
            return checkedFrames >= 5 && Double(usableFrames) / Double(checkedFrames) >= 0.6
        }
        let failed = error.map { ($0 as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true } ?? false
        Task { @MainActor in
            self.timer?.invalidate(); self.timer = nil
            self.recording = false; self.ready = false; self.message = "摄像头已关闭"
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                guard !self.discarded else { throw CancellationError() }
                guard !failed else { throw FaceError.message("录像未完成，已停止上传。") }
                guard quality else { throw FaceError.message("面部在画面中停留不足或存在多人，本次仅保留本地视频，不上传。") }
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.duration).seconds >= 15 else { throw FaceError.message("采集不足 15 秒，不提交分析。") }
                guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw FaceError.message("无法转换视频格式。") }
                let mp4 = url.deletingLastPathComponent().appendingPathComponent("measurement.mp4")
                exporter.outputURL = mp4; exporter.outputFileType = .mp4
                await exporter.export()
                guard !self.discarded else { throw CancellationError() }
                guard exporter.status == .completed else { throw FaceError.message("视频转换失败，原片已留在本机。") }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: mp4.path)
                self.onFinished?(.success(mp4))
            } catch { self.onFinished?(.failure(error)) }
        }
    }
}
