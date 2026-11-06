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
