import SwiftUI
import AVFoundation

struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer
    func makeNSView(context: Context) -> PreviewView {
        PreviewView(preview: layer)
    }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        init(preview: AVCaptureVideoPreviewLayer) {
            self.preview = preview
            super.init(frame: .zero); wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
