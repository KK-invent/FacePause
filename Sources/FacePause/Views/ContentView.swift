import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraService
    @LocalViewState<Bool> private var understood = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar.padding(.bottom, 30)
                if let error = model.error { errorBanner(error).padding(.bottom, 22) }
                if let result = model.result {
                    ResultsView(result: result, sample: model.isSample, deepSeek: model.deepSeek,
                                onOpenSettings: { model.onOpenSettings?() }) {
                        model.clearMeasurement(); model.beginCapture()
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
                } else {
                    home.transition(.opacity)
                }
                footer.padding(.top, 40)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 36).padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .foregroundStyle(Theme.ink)
        .tint(Theme.red)
        .animation(Theme.spring, value: model.result == nil)
        .animation(Theme.spring, value: model.error)
        .sheet(isPresented: $model.showChargeSheet) { chargeSheet }
        .onChange(of: model.showChargeSheet) { _, shown in if shown { understood = false } }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandMark(size: 26)
            Text("片刻").font(.system(size: 17, weight: .semibold))
            Spacer()
            statusPill
            Menu {
                Button("打开本地记录") {
                    if FileManager.default.fileExists(atPath: LocalFiles.root.path) {
                        NSWorkspace.shared.open(LocalFiles.root)
                    } else { model.error = "还没有本地记录。完成采集后会在本机生成。" }
                }
                Button("查看示例结果") { model.showSample() }.disabled(model.active)
                Button("预览顶部浮层") { model.previewIsland() }.disabled(model.active)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30).foregroundStyle(Theme.ink)
                    .outlined(Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多")
            IconButton(symbol: "gearshape", help: "设置与连接") { model.onOpenSettings?() }
        }
    }

    private var statusPill: some View {
        let prefs = model.preferences
        let healthy = prefs.enabled && (model.canAnalyze || !prefs.automaticUpload)
        return HStack(spacing: 7) {
            // Black = running normally, red = needs attention, hollow = paused.
            Circle().fill(healthy ? Theme.ink : prefs.enabled ? Theme.red : Theme.paper)
                .overlay(Circle().strokeBorder(prefs.enabled ? Color.clear : Theme.ink, lineWidth: 1))
                .frame(width: 7, height: 7)
            Text(model.scheduleSummary)
            Text("·")
            Text("今日 \(prefs.usedToday)/\(prefs.dailyLimit)").monospacedDigit()
        }
        .font(.caption).foregroundStyle(Theme.ink)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .outlined(Capsule())
        .help("FacePhys：\(model.credentialState) · 每 \(prefs.interval) 分钟 · \(prefs.automaticUpload ? "录完自动上传分析" : "上传前逐次确认")")
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.error = nil } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                .buttonStyle(.plain).help("关闭提示")
        }
        .font(.callout).foregroundStyle(Theme.red)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.red, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Home

    private var home: some View {
        VStack(spacing: 0) {
            PulseOrb(phase: model.phase, countdown: model.countdown, elapsed: camera.elapsed, facePresent: camera.facePresent)
                .reveal(0)
            Text(headline).font(.system(size: 28, weight: .semibold))
                .contentTransition(.opacity).padding(.top, 6).reveal(0.06)
            Text(subline).font(.callout).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                .contentTransition(.opacity).padding(.top, 8).reveal(0.1)
            actions.padding(.top, 26).reveal(0.14)
            if model.uiTest {
                Text("本地验收模式 · 定时与云端上传已停用，不扣费").font(.caption).foregroundStyle(Theme.red).padding(.top, 14)
            }
            HStack(spacing: 8) {
                chip("sun.max", "光线均匀")
                chip("person.crop.square", "正对摄像头")
                chip("speaker.slash", "约 30 秒 · 不录声音")
            }.padding(.top, 44).reveal(0.2)
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.spring, value: model.phase)
    }

    private var headline: String {
        switch model.phase {
        case .countdown: return "放松，马上开始"
        case .starting: return "正在确认面部入镜"
        case .recording: return "此刻，只需自然坐着。"
        case .preparing: return "正在整理视频"
        case .analyzing: return "FacePhys 分析中"
        case .failed: return "本次检测已停止"
        default: return model.pending ? "本次视频已保存在本机。" : "停一会儿，看看此刻。"
        }
    }
    private var subline: String {
        if model.phase == .idle && !model.pending { return "定时检测前，顶部会先提醒 5 秒，再安静采集约 30 秒。" }
        if model.phase == .recording { return "摄像头画面保持隐藏，进度也显示在屏幕顶部" }
        return model.status
    }

    @ViewBuilder private var actions: some View {
        if model.processingVideo {
            Button("取消本次") { model.cancelCapture() }.buttonStyle(PillButtonStyle(prominent: false))
        } else if model.busy {
            EmptyView()  // the orb already spins; the status line says what is happening
        } else if let video = model.video {
            HStack(spacing: 10) {
                Button("上传并分析…") { model.requestAnalysis() }.buttonStyle(PillButtonStyle())
                Button("预览视频") { NSWorkspace.shared.open(video) }.buttonStyle(PillButtonStyle(prominent: false))
                Button("仅保留本地") { model.clearMeasurement() }.buttonStyle(PillButtonStyle(prominent: false))
            }
        } else {
            VStack(spacing: 14) {
                Button("立即检测") { model.beginCapture() }.buttonStyle(PillButtonStyle())
                if !model.canAnalyze && !model.uiTest {
                    Button("连接 FacePhys 后才能云端分析 →") { model.onOpenSettings?() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .outlined(Capsule())
    }

    private var footer: some View {
        Text("面部视频得到的是估算值，仅供个人状态参考，不作诊断。身体不适时，以自身感受和专业评估为准。")
            .font(.caption2).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: Charge confirmation

    private var chargeSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("确认上传与扣费", systemImage: "icloud.and.arrow.up").font(.title2.weight(.semibold))
            Text("本次面部视频会上传至 FacePhys 云端处理，消耗你账户的 Token（服务额度）。")
            Text("费用按视频输入量与 Key 所选输出字段集计算。当前接口不提供准确的预报价，本 App 不承诺固定费用。请先查看控制台中的字段集与计费说明。")
                .font(.callout)
            Link("查看 FacePhys 计费说明", destination: URL(string: "https://www.facephys.com/console/docs?s=billing")!)
                .font(.callout)
            Text("视频和完整结果保留在本机；云端留存以 FacePhys 政策为准。确认后即提交本次分析，关闭应用也不保证撤销云端处理。")
                .font(.caption)
            Toggle("我已了解上传范围和计费方式，同意本次扣费", isOn: $understood)
            HStack(spacing: 10) {
                Spacer()
                Button("暂不上传") { model.showChargeSheet = false }.keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                Button("确认上传并分析") {
                    model.showChargeSheet = false
                    Task { await model.analyze() }
                }.buttonStyle(PillButtonStyle(compact: true)).disabled(!understood)
            }
        }.padding(28).frame(width: 480).background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.red)
    }
}
