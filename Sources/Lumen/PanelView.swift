import SwiftUI
import AppKit

/// The dropdown panel. Three ring gauges (CPU / RAM / SSD) over a list of the
/// memory-hungriest apps, each with its real icon and a one-click quit.
/// Designed to feel native and quiet — color only appears when something needs
/// attention.
struct PanelView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var themeStore: ThemeStore
    var onQuit: () -> Void
    var onOpenStorage: () -> Void = {}
    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rings
            Divider().overlay(.primary.opacity(0.08)).padding(.horizontal, 16)
            processSection
            footer
        }
        .frame(width: 320)
        .background(ThemeBackground(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        )
        .environment(\.colorScheme, theme.scheme)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Lumen")
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
                      fill: theme.ringFill(monitor.system.cpuPercent))
            RingGauge(label: "Memory", percent: monitor.system.ramPercent,
                      detail: Fmt.bytes(monitor.system.ramUsedBytes),
                      fill: theme.ringFill(monitor.system.ramPercent))
            RingGauge(label: "Disk", percent: monitor.system.diskPercent,
                      detail: Fmt.compact(monitor.system.diskTotalBytes - monitor.system.diskUsedBytes) + " free",
                      fill: theme.ringFill(monitor.system.diskPercent, warnAt: 85, dangerAt: 95),
                      onTap: onOpenStorage)
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
        HStack(spacing: 7) {
            ForEach(Theme.all) { t in
                ThemeSwatch(theme: t, selected: t.id == theme.id) {
                    themeStore.select(t.id)
                }
            }
            Spacer()
            Button(action: onQuit) {
                Text("Quit Lumen")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.04))
    }
}

// MARK: - Ring gauge

private struct RingGauge: View {
    let label: String
    let percent: Double
    let detail: String
    let fill: AnyShapeStyle
    var onTap: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 5.5)
                Circle()
                    .trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(
                        fill,
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

            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0.45)
                }
            }
            Text(detail)
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering && onTap != nil ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap?() }
        .help(onTap != nil ? "Open Storage — see what's filling your disk" : "")
    }
}

// MARK: - Theme swatch

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(theme.ringFill(45))
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 0.5))
                .overlay(
                    Circle().strokeBorder(.primary.opacity(selected ? 0.85 : 0), lineWidth: 1.5)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .help(theme.name)
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
