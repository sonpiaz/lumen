import SwiftUI
import AppKit

// MARK: - Model

/// Drives an on-demand disk scan and the cleanup actions. Lives only while the
/// Storage window is open.
@MainActor
final class StorageModel: ObservableObject {
    enum Phase { case idle, scanning, done }

    @Published var phase: Phase = .idle
    @Published var capacity: (used: Int64, total: Int64, free: Int64) = (0, 0, 0)
    @Published var reclaimables: [Reclaimable] = []
    @Published var navStack: [DiskNode] = []
    @Published var progressBytes: Int64 = 0
    @Published var needsFullDiskAccess = false
    @Published var cleaning: Set<String> = []

    private var scanner: DiskScanner?
    private var progressTimer: Timer?

    var current: DiskNode? { navStack.last }

    /// Bytes the one-click actions can actually free (excludes reveal-only rows).
    var reclaimableTotal: Int64 {
        reclaimables
            .filter { $0.action == .delete || $0.action == .emptyTrash }
            .reduce(Int64(0)) { $0 + $1.size }
    }

    func startIfNeeded() { if phase == .idle { rescan() } }

    func rescan() {
        scanner?.isCancelled = true
        let scanner = DiskScanner()
        self.scanner = scanner
        phase = .scanning
        reclaimables = []
        navStack = []
        progressBytes = 0
        needsFullDiskAccess = false
        capacity = scanner.capacity()
        startProgressTimer()

        // Reclaimables (targeted, fast) and the home tree run concurrently so
        // the actionable cleanup list appears without waiting for the full walk.
        Task.detached(priority: .utility) {
            let recl = scanner.computeReclaimables()
            await MainActor.run {
                guard self.scanner === scanner else { return }
                self.reclaimables = (recl + self.reclaimables).sorted { $0.size > $1.size }
            }
        }
        Task.detached(priority: .utility) {
            let root = scanner.scanHome()
            let nm = scanner.nodeModulesSummary()
            await MainActor.run {
                guard self.scanner === scanner else { return }
                self.navStack = [root]
                self.needsFullDiskAccess = scanner.hadPermissionError
                if let nm {
                    self.reclaimables = (self.reclaimables + [nm]).sorted { $0.size > $1.size }
                }
                self.progressBytes = scanner.bytesScanned
                self.phase = .done
                self.stopProgressTimer()
            }
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.scanner else { return }
                self.progressBytes = s.bytesScanned
            }
        }
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: Navigation

    func drill(_ node: DiskNode) {
        guard node.isDirectory, !node.isAggregate else { return }
        navStack.append(node)
    }

    func popTo(_ index: Int) {
        guard index >= 0, index < navStack.count else { return }
        navStack = Array(navStack.prefix(index + 1))
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Cleanup

    func clean(_ item: Reclaimable) {
        if item.action == .reveal {
            if let url = item.url { reveal(url) }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Free up \(Fmt.bytes(UInt64(max(0, item.size))))?"
        switch item.action {
        case .emptyTrash:
            alert.informativeText = "Permanently empty the Trash. This cannot be undone."
            alert.addButton(withTitle: "Empty Trash")
        case .deleteSnapshots:
            alert.messageText = "Delete \(item.snapshotDates.count) local snapshots?"
            alert.informativeText = "Removes Time Machine local snapshots to reclaim disk space. Your external Time Machine backups are untouched."
            alert.addButton(withTitle: "Delete Snapshots")
        default:
            alert.informativeText = "\(item.note). This deletes the files now."
            alert.addButton(withTitle: "Clean")
        }
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleaning.insert(item.id)
        let action = item.action
        let url = item.url
        let dates = item.snapshotDates
        let id = item.id

        Task.detached(priority: .userInitiated) {
            switch action {
            case .delete, .emptyTrash:
                if let url { Self.emptyContents(of: url) }
            case .deleteSnapshots:
                let scanner = DiskScanner()
                for d in dates { _ = scanner.runTmutil(["deletelocalsnapshots", d]) }
            case .reveal:
                break
            }
            let freshSize = url.map { DiskScanner().directorySize($0) } ?? 0
            let cap = DiskScanner().capacity()
            await MainActor.run {
                self.cleaning.remove(id)
                self.capacity = cap
                if action == .deleteSnapshots {
                    self.reclaimables.removeAll { $0.id == id }
                } else if let idx = self.reclaimables.firstIndex(where: { $0.id == id }) {
                    if freshSize <= 0 {
                        self.reclaimables.remove(at: idx)
                    } else {
                        self.reclaimables[idx].size = freshSize
                    }
                }
            }
        }
    }

    /// Deletes everything *inside* a directory (keeps the directory itself, which
    /// the system may expect to exist).
    nonisolated private static func emptyContents(of dir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: []) else { return }
        for item in items { try? fm.removeItem(at: item) }
    }
}

// MARK: - Window

@MainActor
final class StorageWindowController {
    private var window: NSWindow?
    private let model = StorageModel()
    private let themeStore: ThemeStore

    init(themeStore: ThemeStore) { self.themeStore = themeStore }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            model.startIfNeeded()
            return
        }
        let host = NSHostingView(rootView: StorageView(model: model, themeStore: themeStore))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "Lumen — Storage"
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified
        win.isOpaque = false                 // let the frosted glass show the desktop
        win.backgroundColor = .clear
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        model.rescan()
    }
}
