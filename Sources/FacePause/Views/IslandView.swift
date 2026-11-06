import SwiftUI

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraService

    /// Capture and upload stay a slim capsule, recording adds an ECG strip,
    /// and outcomes that need a glance or a decision expand.
    static func expanded(_ phase: MeasurementPhase) -> Bool { [.complete, .failed, .awaitingApproval].contains(phase) }
    static func size(for phase: MeasurementPhase) -> CGSize {
        if expanded(phase) { return CGSize(width: 420, height: 128) }
        if phase == .recording { return CGSize(width: 420, height: 112) }
        return CGSize(width: 380, height: 64)
    }
    private var expanded: Bool { Self.expanded(model.phase) }
    private var recording: Bool { model.phase == .recording }

    private var title: String {
        switch model.phase {
        case .countdown: return "给自己一个片刻"
        case .starting: return "正在检查面部"
        case .recording: return "安静采集中"
        case .preparing: return "正在整理视频"
        case .analyzing: return "FacePhys 分析中"
        case .awaitingApproval: return "本次采集完成"
        case .complete: return model.isSample ? "效果预览 · 示例" : "此刻的参考"
        case .failed: return "本次检测已停止"
        case .idle: return "片刻"
        }
    }
    private var subtitle: String {
        if model.phase == .recording { return camera.facePresent ? "保持正面、自然呼吸 · 只录视频" : "面部离开画面，请重新正对摄像头" }
        if model.phase == .countdown { return "即将安静采集约 30 秒，可以取消" }
        if model.phase == .complete, let result = model.result {
            return model.isSample ? "仅展示浮层效果，没有检测或扣费" : (result.suitableForAdvice ? "可以把视线移开屏幕，放松一下。" : "信号偏弱，改善光线后再测。")
        }
        return model.status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.paper).lineLimit(expanded ? 2 : 1)
                }
                Spacer(minLength: 6)
                trailing
                if model.processingVideo {
                    roundButton("xmark", help: "取消本次检测") { model.cancelCapture() }
                }
                roundButton("chevron.up", help: "收起浮层，检测继续") { model.onHidePanel?() }
            }
            if expanded {
                Spacer(minLength: 10)
                bottomRow.transition(.opacity.combined(with: .offset(y: 6)))
            } else if recording {
                ECGTrace(lineWidth: 1.8)
                    .frame(height: 38).padding(.top, 8).padding(.horizontal, 2)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, expanded || recording ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: expanded || recording ? 30 : 32, style: .continuous).fill(Theme.ink))
        .animation(Theme.spring, value: model.phase)
        .preferredColorScheme(.dark)
    }

    /// Brand glyph inside a ring that shows countdown / recording progress.
    private var badge: some View {
        ZStack {
            Circle().stroke(Theme.paper, lineWidth: 1)
            progressRing
            if recording {
                BeatingHeartIcon(size: 14)
            } else {
                Image(nsImage: BrandIcon.menuImage).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 17, height: 15).foregroundStyle(Theme.glow)
            }
        }.frame(width: 38, height: 38)
    }
    @ViewBuilder private var progressRing: some View {
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        switch model.phase {
        case .recording:
            Circle().trim(from: 0, to: min(1, Double(camera.elapsed) / 30)).stroke(Theme.glow, style: style)
                .rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: camera.elapsed)
        case .countdown:
            Circle().trim(from: 0, to: Double(model.countdown) / 5).stroke(Theme.glow, style: style)
                .rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.6), value: model.countdown)
        case .starting, .preparing, .analyzing:
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                Circle().trim(from: 0, to: 0.25).stroke(Theme.glow, style: style)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
            }
        case .complete:
            Circle().stroke(Theme.glow, lineWidth: 2.5)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.phase {
        case .countdown:
            number(model.countdown)
        case .recording:
            number(max(0, 30 - camera.elapsed))
        default:
            EmptyView()
        }
    }
    private func number(_ value: Int) -> some View {
        Text("\(value)").font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            .foregroundStyle(Theme.glow).contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: value).padding(.trailing, 4)
    }

    @ViewBuilder private var bottomRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if model.phase == .awaitingApproval {
                Button("仅保留本地") { model.clearMeasurement() }.buttonStyle(IslandButtonStyle(prominent: false))
                Spacer()
                Button(model.canAnalyze ? "确认上传…" : "连接 FacePhys") { model.requestAnalysis() }.buttonStyle(IslandButtonStyle())
            } else {
                if let hr = model.result?.heartRate {
                    Text(String(format: "%.0f", hr)).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.glow)
                    Text("次/分 · 心率估算").font(.caption).foregroundStyle(Theme.paper)
                }
                Spacer()
                Button("查看详情") { model.onOpenDashboard?(); model.onHidePanel?() }.buttonStyle(IslandButtonStyle())
            }
        }.padding(.leading, 4)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24).overlay(Circle().strokeBorder(Theme.paper, lineWidth: 1))
                .contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(Theme.paper).help(help)
    }
}

private struct IslandButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .foregroundStyle(Theme.paper)
            .background(Capsule().fill(prominent ? Theme.red : Theme.ink))
            .overlay(Capsule().strokeBorder(prominent ? Theme.red : Theme.paper, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
