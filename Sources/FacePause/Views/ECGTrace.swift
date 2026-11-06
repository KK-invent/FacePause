import SwiftUI

/// Decorative heartbeat rhythm shown while recording. It runs at a fixed pace;
/// no live measurement exists until FacePhys returns a result.
enum ECGRhythm {
    static let bpm: Double = 72
    /// Beat phase (0..<1) at a given time; the R peak sits at 0.30.
    static func phase(_ time: TimeInterval, bpm: Double = ECGRhythm.bpm) -> Double {
        let beats = time * bpm / 60
        return beats - beats.rounded(.down)
    }
    /// Stylised PQRST amplitude, roughly -0.3...1.
    static func wave(_ p: Double) -> Double {
        func bump(_ center: Double, _ width: Double) -> Double { exp(-pow(p - center, 2) / (2 * width * width)) }
        return 0.09 * bump(0.12, 0.025) - 0.11 * bump(0.27, 0.008) + 1.0 * bump(0.30, 0.010)
            - 0.30 * bump(0.325, 0.009) + 0.2 * bump(0.52, 0.045)
    }
    /// 0...1 kick right after each R peak, for a synced heart pulse.
    static func kick(_ p: Double) -> Double { exp(-pow(p - 0.33, 2) / (2 * 0.045 * 0.045)) }
    /// "Lub-dub": the main kick followed by a smaller second sound.
    static func lubDub(_ p: Double) -> Double { kick(p) + 0.45 * exp(-pow(p - 0.5, 2) / (2 * 0.04 * 0.04)) }
}

/// Monitor-style sweep: the newest signal enters on the right behind a white head dot.
struct ECGTrace: View {
    var color: Color = Theme.glow
    var window: Double = 2.6
    var lineWidth: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                let radius = lineWidth * 1.8
                let usable = size.width - radius * 2  // keep the head dot inside the bounds
                let steps = max(Int(usable / 1.5), 2)
                var path = Path()
                var head = CGPoint.zero
                for index in 0...steps {
                    let fraction = Double(index) / Double(steps)
                    let t = now - window * (1 - fraction)
                    let point = CGPoint(x: radius + usable * fraction,
                                        y: size.height * (0.64 - 0.56 * ECGRhythm.wave(ECGRhythm.phase(t))))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    head = point
                }
                graphics.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                graphics.fill(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
                              with: .color(Theme.paper))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Heart that beats "lub-dub". Defaults to the decorative rhythm; pass a measured `bpm` to follow a result.
struct BeatingHeartIcon: View {
    var size: CGFloat = 14
    var color: Color = Theme.glow
    var bpm: Double = ECGRhythm.bpm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let beat = ECGRhythm.lubDub(ECGRhythm.phase(context.date.timeIntervalSinceReferenceDate, bpm: bpm))
            Image(systemName: "heart.fill").font(.system(size: size))
                .foregroundStyle(color)
                .scaleEffect(1 + 0.2 * (reduceMotion ? 0 : beat))
        }
        .accessibilityHidden(true)
    }
}
