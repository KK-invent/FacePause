import SwiftUI
import FaceCore

struct ResultsView: View {
    let result: PhysMeasurement
    let sample: Bool
    @ObservedObject var deepSeek: DeepSeekStore
    var onOpenSettings: () -> Void
    var onRemeasure: () -> Void
    @LocalViewState<Int> private var tab = 0
    /// +1 when moving to a tab on the right, -1 to the left; content slides in from that side.
    @LocalViewState<CGFloat> private var tabDirection = 1
    @Namespace private var tabSpace

    var body: some View {
        let fieldCount = result.fieldGroups.reduce(0) { $0 + $1.fields.count }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sample ? "示例结果" : "此刻的参考").font(Theme.serif(30))
                    Text(sample ? "演示数值 · 没有检测、上传或扣费" : result.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout).foregroundStyle(sample ? Theme.red : Theme.ink)
                }
                Spacer()
                Button("再测一次", action: onRemeasure).buttonStyle(PillButtonStyle(prominent: false, compact: true))
                    .disabled(deepSeek.isAnalyzing)
            }.reveal(0)
            hero.reveal(0.05)
            HStack(spacing: 12) {
                MetricTile(title: "呼吸估算", value: result.breathingRate, unit: "次/分", icon: "wind", delay: 0.25)
                MetricTile(title: "HRV · RMSSD", value: result.rmssd, unit: "毫秒", icon: "waveform.path.ecg", delay: 0.33)
                MetricTile(title: "HRV · SDNN", value: result.sdnn, unit: "毫秒", icon: "waveform", delay: 0.41)
            }.reveal(0.1)
            Text("“—” 表示本次未返回。信号质量反映采集清晰度，不是准确率或健康分；30 秒的 HRV 只宜谨慎参考，数值不作诊断。")
                .font(.caption).fixedSize(horizontal: false, vertical: true).reveal(0.12)
            tips.reveal(0.16)
            HStack(spacing: 4) {
                tabButton("DeepSeek 解读", 0)
                tabButton("FacePhys 分析", 1)
                tabButton("全部数据 · \(fieldCount) 项", 2)
            }
            .padding(4).outlined(Capsule())
            .padding(.top, 14).reveal(0.2)
            ZStack(alignment: .topLeading) {
                Group {
                    if tab == 0 { DeepSeekAnalysisView(store: deepSeek, openSettings: onOpenSettings) }
                    else if tab == 1 { ProviderReportsView(original: result.originalResponse) }
                    else { AllFieldsView(result: result) }
                }
                .id(tab)
                .transition(.asymmetric(insertion: .offset(x: 28 * tabDirection).combined(with: .opacity),
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            if !sample {
                Label(billingText, systemImage: "creditcard").font(.caption).padding(.top, 4)
            }
        }
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button {
            guard index != tab else { return }
            tabDirection = index > tab ? 1 : -1
            withAnimation(Theme.spring) { tab = index }
        } label: {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tab == index ? Theme.paper : Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background {
                    if tab == index {
                        Capsule().fill(Theme.ink)
                            .matchedGeometryEffect(id: "tab", in: tabSpace)
                    }
                }
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Hero

    private var hero: some View {
        let series = result.heartSeries
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.ink)
            if series.count > 1 {
                HeartSparkline(values: series)
                    .padding(.horizontal, 26).padding(.top, 118).padding(.bottom, 24)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let rate = result.heartRate, rate > 0 {
                        BeatingHeartIcon(size: 15, bpm: rate)
                    } else {
                        Image(systemName: "heart.fill").font(.callout).foregroundStyle(Theme.red)
                    }
                    Text("心率估算").font(.callout).foregroundStyle(Theme.red)
                    Spacer()
                    qualityChip
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RollingNumber(value: result.heartRate, delay: 0.15)
                        .font(.system(size: 64, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Text("次 / 分").font(.callout).foregroundStyle(Theme.paper)
                    Spacer()
                    if let lo = series.min(), let hi = series.max(), series.count > 1 {
                        Text("采集期间 \(Int(lo.rounded()))–\(Int(hi.rounded())) · \(series.count) 个点")
                            .font(.caption).foregroundStyle(Theme.paper).monospacedDigit()
                    }
                }
            }.padding(.horizontal, 26).padding(.top, 22)
        }
        .frame(height: series.count > 1 ? 250 : 150)
        .environment(\.colorScheme, .dark)
    }

    private var qualityChip: some View {
        let good = result.suitableForAdvice
        let text = result.sqi.map { "信号质量 \(Int(($0 * 100).rounded()))%" } ?? "信号质量未知"
        return HStack(spacing: 6) {
            Circle().fill(Theme.red).frame(width: 6, height: 6)
            Text(good ? text : text + " · 建议复测")
        }
        .font(.caption.weight(.medium)).foregroundStyle(good ? Theme.paper : Theme.red)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(Capsule().strokeBorder(good ? Theme.paper : Theme.red, lineWidth: 1))
        .help("服务商返回的信号质量指数（SQI），反映这次采集是否清晰稳定；不是准确率，也不是健康分。达到 65% 且有心率时，App 才给出日常提示。")
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App 本地提示").font(.caption.weight(.semibold))
            ForEach(Array(result.advice.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.caption.monospaced()).foregroundStyle(Theme.red)
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .reveal(0.22 + Double(index) * 0.07)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .outlined(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var billingText: String {
        guard let tokens = result.tokens else { return "FacePhys：未读取到计费字段，请在“全部数据”或其控制台核对" }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        var text = "FacePhys 本次扣除 \(tokens.formatted(format)) Token"
        if let remaining = result.remainingTokens { text += " · 剩余 \(remaining.formatted(format))" }
        return text
    }
}

private struct MetricTile: View {
    let title: String
    let value: Double?
    let unit: String
    let icon: String
    var delay = 0.0
    @LocalViewState<Bool> private var hovering = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                RollingNumber(value: value, delay: delay)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                Text(unit).font(.caption)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(hovering ? Theme.paper : Theme.ink)
        .background {
            // Ink rises from the bottom edge like a level filling up.
            ZStack {
                shape.fill(Theme.paper)
                Rectangle().fill(Theme.ink).scaleEffect(y: hovering ? 1 : 0, anchor: .bottom)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Theme.ink, lineWidth: 1))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Draws the per-point heart rate returned by the service (data.cardiac.hr_list).
/// A white dot leads the line as it draws; hovering scrubs along it and reads out each point.
private struct HeartSparkline: View {
    let values: [Double]
    @LocalViewState<CGFloat> private var drawn = 0
    @LocalViewState<CGFloat?> private var hoverX: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let points = layout(in: geo.size)
            let path = line(points)
            ZStack(alignment: .topLeading) {
                path.trim(from: 0, to: drawn)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                LeadingDot(line: path, progress: drawn).fill(Theme.paper)
                    .opacity(hoverX == nil ? 1 : 0)
                if let hoverX, let index = nearest(to: hoverX, in: points) {
                    readout(at: points[index], value: values[index], size: geo.size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = location.x
                case .ended: hoverX = nil
                }
            }
        }
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(Theme.flow.delay(0.25)) { drawn = 1 } }
        }
    }

    private func readout(at point: CGPoint, value: Double, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.paper).frame(width: 1, height: size.height + 16)
                .position(x: point.x, y: size.height / 2)
            Circle().fill(Theme.red).overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
                .frame(width: 11, height: 11).position(point)
            Text(String(format: "%.1f 次/分", value))
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.paper))
                .fixedSize()
                .position(x: min(max(point.x, 36), size.width - 36), y: -14)
        }
        .allowsHitTesting(false)
    }

    private func nearest(to x: CGFloat, in points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.indices.min { abs(points[$0].x - x) < abs(points[$1].x - x) }
    }
    private func layout(in size: CGSize) -> [CGPoint] {
        guard let lo = values.min(), let hi = values.max(), values.count > 1 else { return [] }
        let span = max(hi - lo, 4)  // avoid exaggerating tiny variation
        let mid = (hi + lo) / 2
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * (0.5 - CGFloat((value - mid) / span) * 0.8))
        }
    }
    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for (previous, point) in zip(points, points.dropFirst()) {
                let midX = (previous.x + point.x) / 2
                path.addCurve(to: point, control1: CGPoint(x: midX, y: previous.y), control2: CGPoint(x: midX, y: point.y))
            }
        }
    }
}

/// A dot that sits at the end of `path` trimmed to `progress`, so it rides the line as it draws.
private struct LeadingDot: Shape {
    let line: Path
    var progress: CGFloat
    var radius: CGFloat = 3.6
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        guard progress > 0.002, let point = line.trimmedPath(from: 0, to: progress).currentPoint else { return Path() }
        return Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}
