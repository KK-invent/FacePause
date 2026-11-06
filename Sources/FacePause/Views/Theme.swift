import SwiftUI
import AppKit

/// Strict three-colour palette: pure black, pure white and one red. No gradients, glows or shadows.
enum Theme {
    static let red = Color(red: 0.93, green: 0.07, blue: 0.13)
    static let glow = red
    static let accent = red
    static let ink = Color.black
    static let paper = Color.white
    static let onAccent = Color.white
    static let spring = Animation.spring(response: 0.48, dampingFraction: 0.84)
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
            configuration.label
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .padding(.horizontal, compact ? 14 : 28).padding(.vertical, compact ? 6 : 11)
                .foregroundStyle(prominent ? Theme.paper : hovering ? Theme.paper : Theme.ink)
                .background {
                    Capsule().fill(prominent ? Theme.red : hovering ? Theme.ink : Theme.paper)
                        .overlay(Capsule().strokeBorder(prominent ? Theme.red : Theme.ink, lineWidth: 1))
                }
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : hovering ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.18), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @LocalViewState<Bool> private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovering ? Theme.ink : Theme.paper))
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
                .contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(hovering ? Theme.paper : Theme.ink).help(help)
            .onHover { hovering = $0 }.animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Staggered fade-and-rise entrance.
private struct Reveal: ViewModifier {
    let delay: Double
    @LocalViewState<Bool> private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
            .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(delay)) { shown = true } }
    }
}

extension View {
    func reveal(_ delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }
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
