import SwiftUI
import AppKit

/// The dropdown panel. Three ring gauges (CPU / RAM / SSD) over a list of the
/// memory-hungriest apps, each with its real icon and a one-click quit.
/// Designed to feel native and quiet — color only appears when something needs
/// attention.
struct PanelView: View {
    @ObservedObject var monitor: Monitor
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rings
            Divider().padding(.horizontal, 16)
            processSection
            footer
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Pulse")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Text(MachineInfo.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: Gauges

    private var rings: some View {
        HStack(spacing: 0) {
            RingGauge(label: "CPU", percent: monitor.system.cpuPercent,
                      detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores",
                      tint: Palette.tint(monitor.system.cpuPercent))
            RingGauge(label: "Memory", percent: monitor.system.ramPercent,
                      detail: Fmt.bytes(monitor.system.ramUsedBytes),
                      tint: Palette.tint(monitor.system.ramPercent))
            RingGauge(label: "Disk", percent: monitor.system.diskPercent,
                      detail: Fmt.compact(monitor.system.diskTotalBytes - monitor.system.diskUsedBytes) + " free",
                      tint: Palette.tint(monitor.system.diskPercent, red: 95, orange: 85))
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 14)
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOP APPS BY MEMORY")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 6)

            if monitor.processes.isEmpty {
                Text("Reading processes…")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 1) {
                    ForEach(monitor.processes) { proc in
                        ProcessRow(proc: proc) { force in
                            monitor.kill(proc, force: force)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "option")
                .font(.system(size: 9, weight: .semibold))
            Text("click ⏏ to force quit")
                .font(.system(size: 10))
            Spacer()
            Button(action: onQuit) {
                Text("Quit Pulse")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.black.opacity(0.04))
    }
}

// MARK: - Ring gauge

private struct RingGauge: View {
    let label: String
    let percent: Double
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 5.5)
                Circle()
                    .trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(
                        tint.gradient,
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.45), value: percent)
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 60, height: 60)

            Text(label)
                .font(.system(size: 11, weight: .medium))
            Text(detail)
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Process row

private struct ProcessRow: View {
    let proc: ProcGroup
    var onKill: (_ force: Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: IconLoader.icon(for: proc.iconPath))
                .resizable()
                .frame(width: 18, height: 18)

            Text(proc.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if proc.cpuPercent >= 1 {
                Text(String(format: "%.0f%%", proc.cpuPercent))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(Fmt.bytes(proc.memoryBytes))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)

            Button {
                let force = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
                onKill(force)
            } label: {
                Image(systemName: "eject.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Color.white : .clear)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(hovering ? Color.red : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Quit \(proc.name) — ⌥-click to force quit")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Helpers

/// Tasteful, quiet color ramp: neutral until it matters, then orange, then red.
enum Palette {
    static func tint(_ pct: Double, red: Double = 88, orange: Double = 70) -> Color {
        if pct >= red { return .red }
        if pct >= orange { return .orange }
        return .accentColor
    }
}

/// System icon for an app/executable path, cached so refreshes stay cheap.
enum IconLoader {
    private static let cache = NSCache<NSString, NSImage>()
    private static let fallback: NSImage = {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }()

    static func icon(for path: String?) -> NSImage {
        guard let path, !path.isEmpty else { return fallback }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 18, height: 18)
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

/// Machine summary like "M3 Pro · 36 GB" for the header.
enum MachineInfo {
    static let summary: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let cpu = String(cString: brand).replacingOccurrences(of: "Apple ", with: "")
        let ramGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return cpu.isEmpty ? "\(ramGB) GB" : "\(cpu) · \(ramGB) GB"
    }()
}
