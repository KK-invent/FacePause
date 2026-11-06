import SwiftUI
import FaceCore

struct ResultsView: View {
    let result: PhysMeasurement
    let sample: Bool
    @ObservedObject var deepSeek: DeepSeekStore
    var onOpenSettings: () -> Void
    var onRemeasure: () -> Void
    @LocalViewState<Int> private var tab = 0
    @Namespace private var tabSpace

    var body: some View {
        let fieldCount = result.fieldGroups.reduce(0) { $0 + $1.fields.count }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sample ? "示例结果" : "此刻的参考").font(.system(size: 28, weight: .semibold))
                    Text(sample ? "演示数值 · 没有检测、上传或扣费" : result.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout).foregroundStyle(sample ? Theme.red : Theme.ink)
                }
                Spacer()
                Button("再测一次", action: onRemeasure).buttonStyle(PillButtonStyle(prominent: false, compact: true))
                    .disabled(deepSeek.isAnalyzing)
            }.reveal(0)
            hero.reveal(0.05)
            HStack(spacing: 12) {
                MetricTile(title: "呼吸估算", value: result.breathingRate, unit: "次/分", icon: "wind")
                MetricTile(title: "HRV · RMSSD", value: result.rmssd, unit: "毫秒", icon: "waveform.path.ecg")
                MetricTile(title: "HRV · SDNN", value: result.sdnn, unit: "毫秒", icon: "waveform")
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
            Group {
                if tab == 0 { DeepSeekAnalysisView(store: deepSeek, openSettings: onOpenSettings) }
                else if tab == 1 { ProviderReportsView(original: result.originalResponse) }
                else { AllFieldsView(result: result) }
            }.id(tab).transition(.opacity).animation(.easeOut(duration: 0.2), value: tab)
            if !sample {
                Label(billingText, systemImage: "creditcard").font(.caption).padding(.top, 4)
            }
        }
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button { withAnimation(Theme.spring) { tab = index } } label: {
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
                    BeatingHeart(rate: result.heartRate)
                    Text("心率估算").font(.callout).foregroundStyle(Theme.red)
                    Spacer()
                    qualityChip
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.heartRate.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
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
    @LocalViewState<Bool> private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(hovering ? Theme.paper : Theme.ink)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hovering ? Theme.ink : Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Heart icon that beats at the measured rate; static when no rate was returned.
private struct BeatingHeart: View {
    let rate: Double?
    @LocalViewState<Bool> private var beat = false
    var body: some View {
        Image(systemName: "heart.fill").font(.callout).foregroundStyle(Theme.red)
            .scaleEffect(beat ? 1.18 : 0.94)
            .onAppear {
                guard let rate, rate > 0 else { return }
                withAnimation(.easeInOut(duration: 30 / rate).repeatForever(autoreverses: true)) { beat = true }
            }
    }
}

/// Draws the per-point heart rate returned by the service (data.cardiac.hr_list).
private struct HeartSparkline: View {
    let values: [Double]
    @LocalViewState<CGFloat> private var drawn = 0

    var body: some View {
        GeometryReader { geo in
            let points = layout(in: geo.size)
            ZStack {
                line(points).trim(from: 0, to: drawn)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(Theme.paper).frame(width: 7, height: 7)
                        .position(last).opacity(drawn >= 1 ? 1 : 0)
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).delay(0.25)) { drawn = 1 } }
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
