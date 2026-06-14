import Foundation
import Combine

/// The observable state shared between the menu-bar item and the panel.
/// System stats refresh every tick; processes refresh only while the panel
/// is open (set `processesActive`).
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var system: SystemStats = .zero
    @Published private(set) var processes: [ProcGroup] = []

    /// When false, process sampling is skipped to stay idle-cheap.
    var processesActive = false

    private let systemSampler = SystemSampler()
    private let processSampler = ProcessSampler()

    func refresh() {
        system = systemSampler.sample()
        if processesActive {
            processes = processSampler.sample()
        }
    }

    /// Force a process sample immediately (used when the panel opens).
    func refreshProcesses() {
        processes = processSampler.sample()
    }

    /// Seeds representative values for offscreen UI rendering (`--render-panel`).
    func loadPreviewData() {
        system = SystemStats(cpuPercent: 42, ramUsedBytes: 20_080_000_000,
                             ramTotalBytes: 38_654_705_664,
                             diskUsedBytes: 456_000_000_000, diskTotalBytes: 494_000_000_000)
        func g(_ name: String, _ mb: Double, _ cpu: Double, _ path: String) -> ProcGroup {
            ProcGroup(id: name, name: name, memoryBytes: UInt64(mb * 1_048_576),
                      cpuPercent: cpu, pids: [1], iconPath: path)
        }
        processes = [
            g("Mandeck", 15700, 4, "/Applications/Slack.app"),
            g("Code", 3270, 18, "/Applications/Visual Studio Code.app"),
            g("Slack", 686, 2, "/Applications/Slack.app"),
            g("Finder", 496, 0, "/System/Library/CoreServices/Finder.app"),
            g("Notes", 110, 0, "/System/Applications/Notes.app")
        ]
    }

    @discardableResult
    func kill(_ group: ProcGroup, force: Bool) -> Int {
        let n = processSampler.kill(group, force: force)
        // Optimistically drop it so the UI feels responsive.
        processes.removeAll { $0.id == group.id }
        return n
    }
}

/// Byte formatting shared by the UI.
enum Fmt {
    static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    /// Coarser form for tight spots, e.g. "27 GB".
    static func compact(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.0f GB", gb) }
        return String(format: "%.0f MB", Double(b) / 1_048_576)
    }
}
