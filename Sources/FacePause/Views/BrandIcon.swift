import SwiftUI

enum BrandIcon {
    static var appImage: NSImage? {
        Bundle.main.url(forResource: "Logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 4, height: 14), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 15, y: 2, width: 4, height: 14), xRadius: 2, yRadius: 2).fill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: 9)); path.line(to: NSPoint(x: 7, y: 9))
            path.line(to: NSPoint(x: 9, y: 12)); path.line(to: NSPoint(x: 12, y: 6))
            path.line(to: NSPoint(x: 14, y: 9)); path.line(to: NSPoint(x: 16, y: 9))
            path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.black.setStroke(); path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// The brand mark drawn in SwiftUI (same 20×18 geometry as the menu-bar image), so the
/// pulse line can draw itself and the bars can breathe independently.
struct BrandBars: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20, sy = rect.height / 18
        var path = Path()
        for x in [1.0, 15.0] {
            path.addRoundedRect(in: CGRect(x: rect.minX + x * sx, y: rect.minY + 2 * sy, width: 4 * sx, height: 14 * sy),
                                cornerSize: CGSize(width: 2 * sx, height: 2 * sy), style: .continuous)
        }
        return path
    }
}

struct BrandPulse: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20, sy = rect.height / 18
        let points: [(Double, Double)] = [(4, 9), (7, 9), (9, 6), (12, 12), (14, 9), (16, 9)]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * sx, y: rect.minY + point.1 * sy)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
    /// Stroke width matching the menu-bar mark at this drawing size.
    static func lineWidth(for width: CGFloat) -> CGFloat { width / 20 * 2 }
}

/// Brand glyph whose pulse line can be trimmed (`from`...`to`, each 0...1) to make it flow.
struct BrandGlyph: View {
    var from: Double = 0
    var to: Double = 1
    var color: Color = Theme.red
    var body: some View {
        GeometryReader { geo in
            ZStack {
                BrandBars().fill(color)
                BrandPulse().trim(from: from, to: to)
                    .stroke(color, style: StrokeStyle(lineWidth: BrandPulse.lineWidth(for: geo.size.width), lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(20 / 18, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
