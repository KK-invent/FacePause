import AppKit

/// UI-test only: `--snapshot <dir> [--snapshot-times 0.4,2.5]` renders every visible app window
/// to PNG at each time (seconds after launch), then quits. Draws in-process, so it needs no
/// screen-recording permission and never touches the camera or network.
@MainActor enum UISnapshots {
    static func scheduleIfRequested(uiTest: Bool) {
        let args = ProcessInfo.processInfo.arguments
        guard uiTest, let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        var times = [2.5]
        if let t = args.firstIndex(of: "--snapshot-times"), t + 1 < args.count {
            let parsed = args[t + 1].split(separator: ",").compactMap { Double($0) }.sorted()
            if !parsed.isEmpty { times = parsed }
        }
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let start = Date()
            for time in times {
                let wait = time - Date().timeIntervalSince(start)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                capture(into: folder, label: String(format: "%.1fs", time))
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(into folder: URL, label: String) {
        for window in NSApp.windows where window.isVisible && !window.className.contains("StatusBar") {
            guard let view = window.contentView, view.bounds.width > 40,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = (window.title.isEmpty ? "window" : window.title)
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "")
            try? rep.representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("\(name)-\(label).png"))
        }
    }
}
