import AppKit
import SwiftUI

/// Menu-bar-only system monitor. No dock icon (LSUIElement in Info.plist),
/// no main window — everything lives in the status bar + dropdown panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        controller.install()
        menuBar = controller
    }
}

// Headless UI render: `Pulse --render-panel <out.png>` renders the dropdown
// panel with representative data and writes a PNG — lets the design be verified
// without Screen Recording permission.
if let idx = CommandLine.arguments.firstIndex(of: "--render-panel"),
   idx + 1 < CommandLine.arguments.count {
    let outPath = CommandLine.arguments[idx + 1]
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let monitor = Monitor()
        monitor.loadPreviewData()
        let host = NSHostingView(rootView: PanelView(monitor: monitor, onQuit: {}))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)

        // Render inside an offscreen window so SwiftUI lays out + draws.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outPath))
                print("wrote \(outPath) (\(Int(host.bounds.width))×\(Int(host.bounds.height)))")
            }
        }
    }
    exit(0)
}

// Headless menu-bar preview: renders the sparkline + RAM% on a dark bar.
if let idx = CommandLine.arguments.firstIndex(of: "--render-menubar"),
   idx + 1 < CommandLine.arguments.count {
    let outPath = CommandLine.arguments[idx + 1]
    MainActor.assumeIsolated {
        let scale: CGFloat = 4
        let w: CGFloat = 120, h: CGFloat = 24
        let img = NSImage(size: NSSize(width: w * scale, height: h * scale))
        img.lockFocus()
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w * scale, height: h * scale).fill()
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.scaleBy(x: scale, y: scale)
        // Demo CPU history with some shape.
        let demo: [Double] = (0..<32).map { i in
            let wave: Double = 35.0 * sin(Double(i) / 3.0)
            let jitter: Double = Double(i % 5) * 4.0
            return 30.0 + wave + jitter
        }
        let spark = Sparkline.image(demo, size: NSSize(width: 30, height: 15))
        // Emulate the system's template tinting (white on a dark bar).
        let tinted = NSImage(size: spark.size)
        tinted.lockFocus()
        spark.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: spark.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let sparkRect = NSRect(x: 8, y: (h - 15) / 2, width: 30, height: 15)
        tinted.draw(in: sparkRect)
        ("  61%" as NSString).draw(
            at: NSPoint(x: 40, y: (h - 13) / 2),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemOrange
            ])
        img.unlockFocus()
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: outPath))
            print("wrote \(outPath)")
        }
    }
    exit(0)
}

// Headless verification path: `Pulse --selftest` prints one sample and exits.
// Used to validate the Mach/libproc math against `top`/`vm_stat` without a UI.
if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated {
        let sys = SystemSampler()
        let proc = ProcessSampler()
        _ = sys.sample(); _ = proc.sample()   // prime CPU/footprint deltas
        Thread.sleep(forTimeInterval: 1.0)
        let s = sys.sample()
        let groups = proc.sample()
        print(String(format: "CPU: %.1f%%", s.cpuPercent))
        print("RAM: \(Fmt.bytes(s.ramUsedBytes)) / \(Fmt.bytes(s.ramTotalBytes)) " +
              String(format: "(%.1f%%)", s.ramPercent))
        print("SSD: \(Fmt.bytes(s.diskUsedBytes)) / \(Fmt.bytes(s.diskTotalBytes)) " +
              String(format: "(%.1f%%)", s.diskPercent))
        print("--- top apps by memory ---")
        for g in groups {
            print(String(format: "%-28@  %@  cpu %.0f%%",
                         g.name as NSString, Fmt.bytes(g.memoryBytes), g.cpuPercent))
        }
    }
    exit(0)
}

// Top-level `let` retains the delegate for the program's lifetime
// (NSApplication.delegate is a weak reference).
let appDelegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.delegate = appDelegate
    app.run()
}
