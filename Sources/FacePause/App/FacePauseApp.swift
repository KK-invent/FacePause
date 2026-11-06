import SwiftUI
import FaceCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: AppWindows?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)  // the palette is pure white, black and red
        let model = AppModel.shared
        windows = AppWindows(model: model)
        Task {
            // Explicit local provisioning only; the secret arrives through stdin, never argv or a file.
            if !model.uiTest && ProcessInfo.processInfo.arguments.contains("--import-deepseek-key-stdin") {
                do {
                    guard let bytes = try FileHandle.standardInput.read(upToCount: 4096),
                          let key = String(data: bytes, encoding: .utf8) else {
                        throw FaceCore.FaceError.message("未收到 DeepSeek Key。")
                    }
                    try KeychainStore.saveDeepSeek(key)
                } catch { model.deepSeek.error = "DeepSeek Key 导入失败，请在设置中保存。" }
            }
            await model.start()
            if !model.uiTest && ProcessInfo.processInfo.arguments.contains("--deepseek-analyze-latest-once")
                && model.deepSeek.report == nil {
                model.deepSeek.generate()
            }
            Self.applyLayoutPreviewPhase(model)
            if ProcessInfo.processInfo.arguments.contains("--overlay-test") { windows?.openVisualTestWindow() }
            else { windows?.openDashboard() }
        }
    }
    /// UI-test only: `--layout-phase countdown|recording|analyzing` shows that state without camera or network.
    private static func applyLayoutPreviewPhase(_ model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard model.uiTest, let index = args.firstIndex(of: "--layout-phase"), index + 1 < args.count else { return }
        let phases: [String: MeasurementPhase] = ["countdown": .countdown, "recording": .recording, "analyzing": .analyzing]
        guard let phase = phases[args[index + 1]] else { return }
        model.clearMeasurement()
        model.countdown = 3
        model.status = "布局验收 · 未开启摄像头、未上传"
        model.phase = phase
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.prepareToQuit() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--overlay-test") { windows?.openVisualTestWindow() }
        else { windows?.openDashboard() }
        return false
    }
}

@main struct FacePauseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, preferences: model.preferences)
        } label: {
            Image(nsImage: BrandIcon.menuImage).accessibilityLabel("片刻菜单")
        }
        .menuBarExtraStyle(.menu)
    }
}
