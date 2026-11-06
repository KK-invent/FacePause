import SwiftUI

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shell springs open from a small pill at the top; content fades in just behind it.
    @LocalViewState<Bool> private var shellOpen = true
    @LocalViewState<Bool> private var contentShown = true
    /// Completion ring draws itself closed.
    @LocalViewState<Double> private var completeDraw = 1
    /// Bumped on each failure to shake the content once.
    @LocalViewState<Int> private var failures = 0

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
    private var tick: Int { model.phase == .countdown ? model.countdown : -1 }

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
        let shape = RoundedRectangle(cornerRadius: expanded || recording ? 30 : 32, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .leading) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                            .id(title).transition(.push(from: .bottom))
                    }
                    ZStack(alignment: .leading) {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.paper).lineLimit(expanded ? 2 : 1)
                            .id(subtitle).transition(.push(from: .bottom))
                    }
                    .animation(.snappy, value: subtitle)
                }
                .clipped()
                Spacer(minLength: 6)
                trailing
                if model.processingVideo {
                    IslandRoundButton(symbol: "xmark", help: "取消本次检测") { model.cancelCapture() }
                        .transition(.scale.combined(with: .opacity))
                }
                IslandRoundButton(symbol: "chevron.up", help: "收起浮层，检测继续") { model.onHidePanel?() }
            }
            if expanded {
                Spacer(minLength: 10)
                bottomRow.transition(.opacity.combined(with: .offset(y: 8)))
            } else if recording {
                ECGTrace(lineWidth: 1.8)
                    .frame(height: 38).padding(.top, 8).padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .keyframeAnimator(initialValue: 0.0, trigger: failures) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-7, duration: 0.07)
                CubicKeyframe(6, duration: 0.09)
                CubicKeyframe(-4, duration: 0.09)
                CubicKeyframe(2, duration: 0.08)
                SpringKeyframe(0, duration: 0.2)
            }
        }
        .opacity(contentShown ? 1 : 0)
        .scaleEffect(contentShown ? 1 : 0.94, anchor: .top)
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, expanded || recording ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(shape.fill(Theme.ink).scaleEffect(x: shellOpen ? 1 : 0.34, y: shellOpen ? 1 : 0.6, anchor: .top))
        .animation(Theme.spring, value: model.phase)
        .preferredColorScheme(.dark)
        .onAppear {
            if model.phase != .idle { pop() }
            if model.phase == .complete { drawCompleteRing() }
        }
        .onChange(of: model.phase) { old, new in
            if old == .idle && new != .idle { pop() }
            if new == .complete { drawCompleteRing() }
            if new == .failed && !reduceMotion { failures += 1 }
        }
    }

    /// Opens the island from a small pill. Values are reset without animation first, then animated
    /// on the next run-loop turn so SwiftUI does not merge the two writes into a no-op.
    private func pop() {
        guard !reduceMotion else { return }
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { shellOpen = false; contentShown = false }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.66)) { shellOpen = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.14)) { contentShown = true }
        }
    }
    private func drawCompleteRing() {
        guard !reduceMotion else { completeDraw = 1; return }
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { completeDraw = 0 }
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { completeDraw = 1 } }
    }

    /// Brand glyph inside a ring that shows countdown / recording progress.
    private var badge: some View {
        ZStack {
            Circle().stroke(Theme.paper, lineWidth: 1)
            progressRing
            if recording {
                BeatingHeartIcon(size: 14).transition(.scale.combined(with: .opacity))
            } else {
                BrandGlyph().frame(width: 17, height: 15).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 38, height: 38)
        .keyframeAnimator(initialValue: 1.0, trigger: tick) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.14, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
            }
        }
    }
    @ViewBuilder private var progressRing: some View {
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        switch model.phase {
        case .recording:
            Circle().trim(from: 0, to: min(1, Double(camera.elapsed) / 30)).stroke(Theme.glow, style: style)
                .rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: camera.elapsed)
        case .countdown:
            Circle().trim(from: 0, to: Double(model.countdown) / 5).stroke(Theme.glow, style: style)
                .rotationEffect(.degrees(-90)).animation(Theme.springy, value: model.countdown)
        case .starting, .preparing, .analyzing:
            OrganicSpinner(lineWidth: 2.5, period: 1.2)
        case .complete:
            Circle().trim(from: 0, to: completeDraw).stroke(Theme.glow, style: style)
                .rotationEffect(.degrees(-90))
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
            .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private var bottomRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if model.phase == .awaitingApproval {
                Button("仅保留本地") { model.clearMeasurement() }.buttonStyle(IslandButtonStyle(prominent: false))
                Spacer()
                Button(model.canAnalyze ? "确认上传…" : "连接 FacePhys") { model.requestAnalysis() }.buttonStyle(IslandButtonStyle())
            } else {
                if let hr = model.result?.heartRate {
                    RollingNumber(value: hr, fractionDigits: 0, delay: 0.2)
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.glow)
                    Text("次/分 · 心率估算").font(.caption).foregroundStyle(Theme.paper)
                }
                Spacer()
                Button("查看详情") { model.onOpenDashboard?(); model.onHidePanel?() }.buttonStyle(IslandButtonStyle())
            }
        }.padding(.leading, 4)
    }
}

/// Hairline circle button for the island; fills white with a black glyph while hovered.
private struct IslandRoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @LocalViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(hovering ? Theme.ink : Theme.paper)
                .background(Circle().fill(Theme.paper).scaleEffect(hovering ? 1 : 0.2).opacity(hovering ? 1 : 0))
                .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(Theme.springy, value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct IslandButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, prominent: prominent)
    }
    private struct IslandButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @LocalViewState<Bool> private var hovering = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(!prominent && hovering ? Theme.ink : Theme.paper)
                .background {
                    ZStack {
                        Capsule().fill(prominent ? Theme.red : Theme.ink)
                        if !prominent {
                            Capsule().fill(Theme.paper).scaleEffect(x: hovering ? 1 : 0.2, y: hovering ? 1 : 0.5).opacity(hovering ? 1 : 0)
                        }
                    }
                }
                .overlay(Capsule().strokeBorder(prominent ? Theme.red : Theme.paper, lineWidth: 1))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.04 : 1)
                .animation(Theme.springy, value: configuration.isPressed)
                .animation(Theme.springy, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
