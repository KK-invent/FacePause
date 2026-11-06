import SwiftUI

/// The home-screen focal point. At rest it breathes (in 3.4 s, out 4.6 s), lets a hairline ripple go
/// on every out-breath and redraws its pulse line on every in-breath. It becomes a countdown that
/// kicks on each tick, a 30-second progress ring while recording, and a chasing arc while waiting.
struct PulseOrb: View {
    let phase: MeasurementPhase
    let countdown: Int
    let elapsed: Int
    let facePresent: Bool
    private let size: CGFloat = 164
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resting: Bool { [.idle, .complete, .failed, .awaitingApproval].contains(phase) }
    /// Only changes while counting down, so the orb kicks on entry and on every tick.
    private var tick: Int { phase == .countdown ? countdown : -1 }

    var body: some View {
        TimelineView(.animation(minimumInterval: resting ? 1 / 30 : 1 / 60, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = reduceMotion ? 1 : Breath.level(t)
            ZStack {
                if resting && !reduceMotion { ripples(t) }
                if phase == .recording { recordingHalo(t) }
                tickRipple
                Circle().fill(Theme.ink)
                    .frame(width: size, height: size)
                    .scaleEffect(resting ? 0.955 + 0.045 * breath : 1)
                Circle().stroke(Theme.ink, lineWidth: resting ? 0 : 1).frame(width: size + 20, height: size + 20)
                ring.frame(width: size + 20, height: size + 20)
                center(t, breath: breath)
            }
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .keyframeAnimator(initialValue: 1.0, trigger: tick) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.045, duration: 0.1)
                SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
            }
        }
        .animation(Theme.spring, value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Rest

    /// Hairline rings released at the start of each out-breath; they thin away as they spread.
    private func ripples(_ t: Double) -> some View {
        let cycle = Breath.cycle
        let life = cycle * 1.25
        let newest = (t - Breath.inhale).truncatingRemainder(dividingBy: cycle)
        return ZStack {
            ForEach(0..<2, id: \.self) { index in
                let age = newest + Double(index) * cycle
                if age < life {
                    let r = age / life
                    Circle().stroke(Theme.ink, lineWidth: 1.3 * (1 - r))
                        .frame(width: size, height: size)
                        .scaleEffect(1 + 0.42 * (1 - pow(1 - r, 3)))
                }
            }
        }
    }

    /// Pulse line exits to the right at the end of each out-breath and redraws from the left as the in-breath starts.
    private func glyphTrim(_ t: Double) -> (from: Double, to: Double) {
        if reduceMotion { return (0, 1) }
        let p = t.truncatingRemainder(dividingBy: Breath.cycle)
        let drawIn = 1.1, exit = 0.4
        if p < drawIn { return (0, 1 - pow(1 - p / drawIn, 3)) }
        if p > Breath.cycle - exit { return (pow((p - (Breath.cycle - exit)) / exit, 2), 1) }
        return (0, 1)
    }

    // MARK: Active states

    private var tickRipple: some View {
        Color.clear.frame(width: size, height: size)
            .keyframeAnimator(initialValue: 1.0, trigger: tick) { _, v in
                Circle().stroke(Theme.red, lineWidth: 2.5 * (1 - v))
                    .frame(width: size, height: size)
                    .scaleEffect(1 + 0.36 * v)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0)
                    CubicKeyframe(1, duration: 0.95)
                }
            }
    }

    /// Solid red ring that kicks outward on each beat of the decorative rhythm.
    private func recordingHalo(_ t: Double) -> some View {
        let kick = reduceMotion ? 0 : ECGRhythm.kick(ECGRhythm.phase(t))
        return Circle().stroke(Theme.red, lineWidth: 1.5)
            .frame(width: size + 40, height: size + 40)
            .scaleEffect(1 + 0.08 * kick)
    }

    @ViewBuilder private var ring: some View {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round)
        switch phase {
        case .recording:
            Circle().trim(from: 0, to: min(1, Double(elapsed) / 30)).stroke(Theme.red, style: style)
                .rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: elapsed)
        case .countdown:
            Circle().trim(from: 0, to: Double(countdown) / 5).stroke(Theme.red, style: style)
                .rotationEffect(.degrees(-90)).animation(Theme.springy, value: countdown)
        case .starting, .preparing, .analyzing:
            OrganicSpinner(lineWidth: 4).transition(.opacity)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func center(_ t: Double, breath: Double) -> some View {
        let pop = AnyTransition.scale(scale: 0.6).combined(with: .opacity)
        switch phase {
        case .countdown:
            Text("\(countdown)").font(.system(size: 62, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.glow).contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: countdown)
                .transition(pop)
        case .recording:
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    BeatingHeartIcon(size: 15)
                    Text("\(max(0, 30 - elapsed))").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true)).animation(.snappy, value: elapsed)
                }
                ECGTrace(lineWidth: 2).frame(width: size - 54, height: 46)
                Text(facePresent ? "秒" : "请正对摄像头").font(.caption2)
                    .foregroundStyle(facePresent ? Theme.paper : Theme.red)
                    .contentTransition(.opacity).animation(.easeOut(duration: 0.2), value: facePresent)
            }
            .offset(y: 4)
            .transition(pop)
        default:
            let trim = glyphTrim(t)
            BrandGlyph(from: trim.from, to: trim.to)
                .frame(width: 56, height: 50)
                .scaleEffect(resting ? 0.95 + 0.07 * breath : 1)
                .transition(pop)
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .countdown: return "倒计时 \(countdown) 秒"
        case .recording: return "正在采集，剩余 \(max(0, 30 - elapsed)) 秒"
        case .starting, .preparing, .analyzing: return "处理中"
        default: return "片刻"
        }
    }
}

/// Calm breathing curve: 3.4 s in, 4.6 s out (about 7.5 breaths a minute).
enum Breath {
    static let inhale = 3.4
    static let exhale = 4.6
    static var cycle: Double { inhale + exhale }
    /// 0 = empty, 1 = full.
    static func level(_ t: TimeInterval) -> Double {
        let p = t.truncatingRemainder(dividingBy: cycle)
        func ease(_ x: Double) -> Double { 0.5 - 0.5 * cos(.pi * x) }
        return p < inhale ? ease(p / inhale) : 1 - ease((p - inhale) / exhale)
    }
}
