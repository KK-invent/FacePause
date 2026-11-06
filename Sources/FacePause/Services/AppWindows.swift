import SwiftUI
import Combine

@MainActor final class AppWindows {
    private let model: AppModel
    private var dashboard: NSWindow?
    private var settings: NSWindow?
    private var panel: IslandPanel?
    private var visualTestWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        model.onOpenDashboard = { [weak self] in self?.openDashboard() }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onPanelUpdate = { [weak self] in self?.updateIsland() }
        model.onHidePanel = { [weak self] in self?.hideIsland() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionIsland() }
        }
    }
    func openDashboard() {
        if dashboard == nil {
            let window = makeWindow(title: "FacePause · 片刻", size: NSSize(width: 760, height: 780))
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: ContentView(model: model, camera: model.camera))
            window.minSize = NSSize(width: 620, height: 600)
            dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func openSettings() {
        if settings == nil {
            let window = makeWindow(title: "片刻设置", size: NSSize(width: 620, height: 720))
            window.contentView = NSHostingView(rootView: SettingsView(model: model, preferences: model.preferences))
            window.minSize = NSSize(width: 580, height: 650)
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func openVisualTestWindow() {
        let window = makeWindow(title: "片刻浮层 · 布局验收", size: IslandView.size(for: model.phase))
        window.contentView = NSHostingView(rootView: IslandView(model: model, camera: model.camera))
        visualTestWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.center()
        return window
    }
    func updateIsland() {
        dismissTask?.cancel()
        guard model.phase != .idle else { hideIsland(); return }
        if panel == nil {
            let p = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandView.size(for: .complete)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .statusBar; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isReleasedWhenClosed = false
            p.title = "片刻状态浮层"
            p.contentView = NSHostingView(rootView: IslandView(model: model, camera: model.camera))
            panel = p
        }
        if let panel, !panel.isVisible {
            // Drop in from just above its resting place.
            let target = islandFrame()
            panel.setFrame(target.offsetBy(dx: 0, dy: 14), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel?.animator().alphaValue = 1  // cancels a hide that is still fading out
            positionIsland()
        }
        if model.phase == .complete || model.phase == .failed {
            dismissTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                self?.hideIsland()
            }
        }
    }
    private func islandFrame() -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let rect = screen.visibleFrame
        let size = IslandView.size(for: model.phase)
        let width = min(size.width, rect.width - 24)
        return NSRect(x: rect.midX - width / 2, y: rect.maxY - size.height - 8, width: width, height: size.height)
    }
    private func positionIsland() {
        guard let panel, panel.isVisible else { return }
        let target = islandFrame()
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.4, 1)
            panel.animator().setFrame(target, display: true)
        }
    }
    func hideIsland() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in
                guard let panel, panel.alphaValue == 0 else { return }
                panel.orderOut(nil); panel.alphaValue = 1
            }
        })
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
