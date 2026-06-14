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

// Debug: open the Storage window directly with a live scan. `Lumen --open-storage`.
if CommandLine.arguments.contains("--open-storage") {
    let app = NSApplication.shared
    let storage = MainActor.assumeIsolated { () -> StorageWindowController in
        app.setActivationPolicy(.regular)
        let s = StorageWindowController(themeStore: ThemeStore())
        s.show()
        return s
    }
    _ = storage
    app.run()
}

// Render each cosmic theme's panel to <dir>/<id>.png for visual comparison.
if let idx = CommandLine.arguments.firstIndex(of: "--render-themes"),
   idx + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[idx + 1]
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        for theme in Theme.all {
            let monitor = Monitor()
            monitor.loadPreviewData()
            // Frosted glass needs something behind it to frost — render the panel
            // over a stand-in wallpaper so the translucency is visible.
            let preview = ZStack {
                WallpaperBackdrop()
                PanelView(monitor: monitor, themeStore: ThemeStore(theme: theme), onQuit: {}).padding(22)
            }
            .frame(width: 364, height: 429)
            let host = NSHostingView(rootView: preview)
            host.frame = NSRect(x: 0, y: 0, width: 364, height: 429)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: "\(dir)/\(theme.id).png"))
                    print("wrote \(dir)/\(theme.id).png")
                }
            }
        }
    }
    exit(0)
}

// Headless UI render: `Lumen --render-panel <out.png> [themeId]` renders the
// dropdown panel with representative data — verify the design without Screen
// Recording permission.
if let idx = CommandLine.arguments.firstIndex(of: "--render-panel"),
   idx + 1 < CommandLine.arguments.count {
    let outPath = CommandLine.arguments[idx + 1]
    let theme = idx + 2 < CommandLine.arguments.count
        ? Theme.byId(CommandLine.arguments[idx + 2]) : Theme.vercel
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let monitor = Monitor()
        monitor.loadPreviewData()
        let host = NSHostingView(rootView: PanelView(monitor: monitor, themeStore: ThemeStore(theme: theme), onQuit: {}))
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

// Headless UI render of the Storage window with representative data.
if let idx = CommandLine.arguments.firstIndex(of: "--render-storage"),
   idx + 1 < CommandLine.arguments.count {
    let outPath = CommandLine.arguments[idx + 1]
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = StorageModel()
        let home = FileManager.default.homeDirectoryForCurrentUser
        func node(_ name: String, _ gb: Double, dir: Bool = true) -> DiskNode {
            DiskNode(url: home.appendingPathComponent(name), name: name,
                     isDirectory: dir, size: Int64(gb * 1_073_741_824))
        }
        let root = DiskNode(url: home, name: "Home", isDirectory: true,
                            size: Int64(312.0 * 1_073_741_824), children: [
            node("Library", 124), node("Movies", 78), node("Downloads", 46),
            node("Developer", 34), node("Documents", 18),
            DiskNode(url: home, name: "240 smaller items", isDirectory: false,
                     size: Int64(12.0 * 1_073_741_824), isAggregate: true)
        ])
        model.navStack = [root]
        model.capacity = (used: Int64(456.0 * 1_073_741_824),
                          total: Int64(494.0 * 1_073_741_824),
                          free: Int64(8.0 * 1_073_741_824))
        model.reclaimables = [
            Reclaimable(id: "derived", title: "Xcode DerivedData",
                        note: "Rebuilt automatically on next build",
                        url: home, size: Int64(41.0 * 1_073_741_824), action: .delete),
            Reclaimable(id: "snapshots", title: "Time Machine local snapshots (6)",
                        note: "Hidden copies macOS keeps on disk — often frees the 'missing' space",
                        url: nil, size: 0, action: .deleteSnapshots,
                        snapshotDates: ["2026-06-14-120000"]),
            Reclaimable(id: "caches", title: "App caches",
                        note: "Apps rebuild caches as needed",
                        url: home, size: Int64(8.6 * 1_073_741_824), action: .delete),
            Reclaimable(id: "node_modules", title: "node_modules (37 folders)",
                        note: "Delete per-project when idle; npm install restores",
                        url: home, size: Int64(15.2 * 1_073_741_824), action: .reveal),
            Reclaimable(id: "trash", title: "Trash",
                        note: "Permanently removes trashed items",
                        url: home, size: Int64(3.1 * 1_073_741_824), action: .emptyTrash)
        ]
        model.phase = .done
        let host = NSHostingView(rootView: StorageView(model: model, themeStore: ThemeStore(theme: .vercel)))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outPath))
                print("wrote \(outPath)")
            }
        }
    }
    exit(0)
}

// Verify the real home scan end-to-end: `Lumen --scan-home`.
if CommandLine.arguments.contains("--scan-home") {
    let scanner = DiskScanner()
    let start = ProcessInfo.processInfo.systemUptime
    let recl = scanner.computeReclaimables()
    let root = scanner.scanHome()
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print(String(format: "scanned %@ in %.1fs (permission errors: %@)",
                 Fmt.bytes(UInt64(max(0, scanner.bytesScanned))), elapsed,
                 scanner.hadPermissionError ? "yes" : "no"))
    print("--- largest in home ---")
    for c in root.children.prefix(8) {
        print(String(format: "%10@  %@", Fmt.bytes(UInt64(max(0, c.size))) as NSString, c.name))
    }
    print("--- reclaimable ---")
    for r in recl { print(String(format: "%10@  %@", Fmt.bytes(UInt64(max(0, r.size))) as NSString, r.title)) }
    if let nm = scanner.nodeModulesSummary() {
        print(String(format: "%10@  %@", Fmt.bytes(UInt64(max(0, nm.size))) as NSString, nm.title))
    }
    exit(0)
}

// Verify the scanner's byte math against `du`: `Lumen --scan-test <path>`.
if let idx = CommandLine.arguments.firstIndex(of: "--scan-test"),
   idx + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[idx + 1]
    let scanner = DiskScanner()
    let bytes = scanner.directorySize(URL(fileURLWithPath: path))
    print("\(path): \(Fmt.bytes(UInt64(max(0, bytes)))) (\(bytes) bytes)")
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

// Headless verification path: `Lumen --selftest` prints one sample and exits.
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
