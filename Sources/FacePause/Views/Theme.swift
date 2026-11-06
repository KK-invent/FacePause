import SwiftUI
import AppKit

/// Strict three-colour palette: pure black, pure white and one red. No gradients, glows or shadows.
/// Liveliness comes from motion, rhythm and type rather than extra colour.
enum Theme {
    static let red = Color(red: 0.93, green: 0.07, blue: 0.13)
    static let glow = red
    static let accent = red
    static let ink = Color.black
    static let paper = Color.white
    static let onAccent = Color.white

    /// Default settle for layout and state changes.
    static let spring = Animation.spring(response: 0.48, dampingFraction: 0.84)
    /// Quick, slightly bouncy response for hovers, presses and small kicks.
    static let springy = Animation.spring(response: 0.34, dampingFraction: 0.62)
    /// Long ease-out for numbers that count up and lines that draw in.
    static let flow = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 1.3)

    /// Songti for the few literary lines (brand, headlines). Numbers stay SF Rounded.
    static func serif(_ size: CGFloat) -> Font { .custom("STSongti-SC-Bold", size: size) }
}

/// Plain white window background.
struct Backdrop: View {
    var body: some View { Theme.paper.ignoresSafeArea() }
}

extension View {
    /// White surface with a hairline black outline; replaces tinted fills.
    func outlined<S: InsettableShape>(_ shape: S, line: CGFloat = 1) -> some View {
        background(shape.fill(Theme.paper)).overlay(shape.strokeBorder(Theme.ink, lineWidth: line))
    }

    /// Black fill that grows out from the centre while hovered; the outline stays put.
    func hoverInk<S: InsettableShape>(_ shape: S, active: Bool, outline: Color = Theme.ink) -> some View {
        background {
            ZStack {
                shape.fill(Theme.paper)
                shape.fill(Theme.ink)
                    .scaleEffect(x: active ? 1 : 0.2, y: active ? 1 : 0.5)
                    .opacity(active ? 1 : 0)
                shape.strokeBorder(outline, lineWidth: 1)
            }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, compact: compact)
    }
    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @LocalViewState<Bool> private var hovering = false
        var body: some View {
            let lit = hovering && enabled
            configuration.label
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .padding(.horizontal, compact ? 14 : 28).padding(.vertical, compact ? 6 : 11)
                .foregroundStyle(prominent || lit ? Theme.paper : Theme.ink)
                .background {
                    if prominent { Capsule().fill(Theme.red) }
                }
                .modifier(SecondaryFill(active: !prominent, lit: lit))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.94 : lit ? (prominent ? 1.04 : 1.02) : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(Theme.springy, value: configuration.isPressed)
                .animation(Theme.springy, value: lit)
                .onHover { hovering = $0 }
        }
    }
    private struct SecondaryFill: ViewModifier {
        let active: Bool
        let lit: Bool
        func body(content: Content) -> some View {
            if active { content.hoverInk(Capsule(), active: lit) } else { content }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    /// Degrees the glyph turns while hovered, for a little life (e.g. the settings gear).
    var hoverTurn: Double = 0
    let action: () -> Void
    @LocalViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(hovering ? hoverTurn : 0))
                .frame(width: 30, height: 30)
                .hoverInk(Circle(), active: hovering)
                .contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(hovering ? Theme.paper : Theme.ink).help(help)
            .onHover { hovering = $0 }.animation(Theme.springy, value: hovering)
    }
}

/// Staggered fade-and-rise entrance. Respects Reduce Motion.
private struct Reveal: ViewModifier {
    let delay: Double
    @LocalViewState<Bool> private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985, anchor: .top)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.62, dampingFraction: 0.82).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func reveal(_ delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }
}

/// A number that counts up to its value on appear and rolls to new values.
/// Every frame shows a real formatted number, so digits never jump in width (monospaced).
struct RollingNumber: View {
    let value: Double?
    var fractionDigits = 1
    var delay = 0.0
    @LocalViewState<Double> private var current = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let value {
            CountingText(value: current, fractionDigits: fractionDigits)
                .monospacedDigit()
                .onAppear { roll(to: value) }
                .onChange(of: value) { _, target in roll(to: target) }
                .accessibilityLabel(String(format: "%.\(fractionDigits)f", value))
        } else {
            Text("—")
        }
    }
    private func roll(to target: Double) {
        if reduceMotion { current = target; return }
        withAnimation(Theme.flow.delay(delay)) { current = target }
    }
    private struct CountingText: View, Animatable {
        var value: Double
        let fractionDigits: Int
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        var body: some View { Text(String(format: "%.\(fractionDigits)f", value)) }
    }
}

/// Text that types itself in one character at a time (Latin words stay whole) whenever it changes.
struct StaggerText: View {
    let text: String
    let font: Font
    var step = 0.035
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(Self.tokens(text).enumerated()), id: \.offset) { index, token in
                    Text(token).font(font).modifier(RiseIn(delay: Double(index) * step))
                }
            }
            .id(text)
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
    /// Splits into single CJK characters and whole runs of ASCII letters/digits, keeping Latin kerning.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in text {
            if character.isASCII && (character.isLetter || character.isNumber) {
                word.append(character)
            } else {
                if !word.isEmpty { tokens.append(word); word = "" }
                tokens.append(String(character))
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }
    private struct RiseIn: ViewModifier {
        let delay: Double
        @LocalViewState<Bool> private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func body(content: Content) -> some View {
            content.opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 10)
                .onAppear {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true }
                }
        }
    }
}

/// Indeterminate arc whose head and tail chase each other while it turns.
struct OrganicSpinner: View {
    var lineWidth: CGFloat = 4
    var color: Color = Theme.red
    var period = 1.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let arc = Self.arc(at: context.date.timeIntervalSinceReferenceDate, period: period)
            Circle().trim(from: arc.tail, to: arc.head)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(arc.turn * 360 - 90))
        }
        .accessibilityHidden(true)
    }
    /// Grows the head for half a period, then pulls the tail after it; the base angle advances
    /// by the swept amount each cycle, so consecutive cycles join without a jump.
    static func arc(at time: TimeInterval, period: Double) -> (tail: Double, head: Double, turn: Double) {
        let cycles = time / period
        let cycle = cycles.rounded(.down)
        let p = cycles - cycle
        func ease(_ x: Double) -> Double { 0.5 - 0.5 * cos(.pi * min(max(x, 0), 1)) }
        let sweep = 0.6
        let head = p < 0.5 ? 0.05 + sweep * ease(p / 0.5) : 0.05 + sweep
        let tail = p < 0.5 ? 0 : sweep * ease((p - 0.5) / 0.5)
        let turn = (cycle * sweep + cycles * 0.18).truncatingRemainder(dividingBy: 1)
        return (tail, head, turn)
    }
}

struct BrandMark: View {
    var size: CGFloat = 26
    var body: some View {
        if let icon = BrandIcon.appImage {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(nsImage: BrandIcon.menuImage).renderingMode(.template).resizable().scaledToFit()
                .frame(width: size * 0.8, height: size * 0.72).foregroundStyle(Theme.red)
        }
    }
}
