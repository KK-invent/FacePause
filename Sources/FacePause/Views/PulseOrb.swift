import SwiftUI

/// The home-screen focal point: breathes slowly at rest, becomes a countdown,
/// a 30-second progress ring while recording, and a spinner while waiting.
struct PulseOrb: View {
    let phase: MeasurementPhase
    let countdown: Int
    let elapsed: Int
    let facePresent: Bool
    private let size: CGFloat = 164
    @LocalViewState<Bool> private var breathe = false

    var body: some View {
        ZStack {
            if phase == .recording {
                // Solid red ring that kicks outward on each beat.
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let kick = ECGRhythm.kick(ECGRhythm.phase(context.date.timeIntervalSinceReferenceDate))
                    Circle().stroke(Theme.red, lineWidth: 1.5)
                        .frame(width: size + 40, height: size + 40)
                        .scaleEffect(1 + 0.08 * kick)
                }
            }
            Circle().fill(Theme.ink)
                .frame(width: size, height: size)
                .scaleEffect(breathe ? 1 : 0.96)
            Circle().stroke(Theme.ink, lineWidth: ringVisible ? 1 : 0).frame(width: size + 20, height: size + 20)
            ring.frame(width: size + 20, height: size + 20)
            center
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .animation(Theme.spring, value: phase)
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathe = true } }
    }

    private var ringVisible: Bool { ![.idle, .complete, .failed, .awaitingApproval].contains(phase) }

    @ViewBuilder private var ring: some View {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round)
        switch phase {
        case .recording:
            Circle().trim(from: 0, to: min(1, Double(elapsed) / 30)).stroke(Theme.red, style: style)
                .rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: elapsed)
        case .countdown:
            Circle().trim(from: 0, to: Double(countdown) / 5).stroke(Theme.red, style: style)
                .rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.6), value: countdown)
        case .starting, .preparing, .analyzing:
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                Circle().trim(from: 0, to: 0.24).stroke(Theme.red, style: style)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360))
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var center: some View {
        switch phase {
        case .countdown:
            Text("\(countdown)").font(.system(size: 62, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.glow).contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: countdown)
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
            }.offset(y: 4)
        default:
            Image(nsImage: BrandIcon.menuImage).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 56, height: 50).foregroundStyle(Theme.glow)
                .scaleEffect(breathe ? 1.04 : 0.96)
        }
    }
}
