import AppKit
import SwiftUI

/// Owns the status-bar item, the live title, the refresh timer, and the
/// dropdown panel. Keeps process sampling off until the panel is shown.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private let monitor = Monitor()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var timer: Timer?
    private var cpuHistory: [Double] = []   // recent CPU samples for the sparkline

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }
        statusItem = item

        // Prime two samples so CPU deltas are valid, then start the cadence.
        monitor.refresh()
        tick()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        monitor.refresh()
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }

        // Live CPU sparkline — the "pulse". Kept as a template image so macOS
        // tints it correctly for light/dark menu bars.
        cpuHistory.append(monitor.system.cpuPercent)
        if cpuHistory.count > 32 { cpuHistory.removeFirst(cpuHistory.count - 32) }
        button.image = Sparkline.image(cpuHistory, size: NSSize(width: 30, height: 15))

        // RAM percentage — the number that actually predicts trouble. Stays
        // monochrome until it climbs, then warms to orange/red.
        let ram = Int(monitor.system.ramPercent.rounded())
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        ]
        if ram >= 85 { attrs[.foregroundColor] = NSColor.systemRed }
        else if ram >= 72 { attrs[.foregroundColor] = NSColor.systemOrange }
        button.attributedTitle = NSAttributedString(string: " \(ram)%", attributes: attrs)
    }

    // MARK: Panel

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        monitor.processesActive = true
        monitor.refreshProcesses()

        let view = PanelView(monitor: monitor) { [weak self] in
            self?.dismissPanel()
            NSApp.terminate(nil)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.contentView = hosting
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.delegate = self

        if let button = statusItem?.button, let win = button.window {
            let frame = win.convertToScreen(button.frame)
            let size = hosting.fittingSize
            let x = frame.midX - size.width / 2
            let y = frame.minY - size.height - 6
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newPanel.orderFrontRegardless()
        panel = newPanel

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissPanel()
        }
    }

    private func dismissPanel() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        monitor.processesActive = false
    }
}
