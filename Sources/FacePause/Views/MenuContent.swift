import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    var body: some View {
        Text("片刻 · FacePause")
        Text(model.scheduleSummary)
        Text("今日分析 \(preferences.usedToday) / \(preferences.dailyLimit) 次")
        Divider()
        Button(model.active ? "检测进行中…" : "立即检测") { model.beginCapture() }
            .disabled(model.active || model.pending)
        if model.processingVideo { Button("取消本次检测") { model.cancelCapture() } }
        if model.pending && !model.active {
            Button("处理本次视频…") { model.onOpenDashboard?() }
        }
        Toggle("定时检测", isOn: $preferences.enabled)
        Button("显示状态浮层") { model.onPanelUpdate?() }
        Divider()
        Button("打开主窗口") { model.onOpenDashboard?() }
        Button("设置…") { model.onOpenSettings?() }.keyboardShortcut(",")
        Button("预览灵动岛效果") { model.previewIsland() }
        Divider()
        Button("退出片刻") { model.prepareToQuit(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
