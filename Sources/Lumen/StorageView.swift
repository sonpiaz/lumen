import SwiftUI
import AppKit

/// The Storage window: where your SSD space is going, and what's safe to clear.
struct StorageView: View {
    @ObservedObject var model: StorageModel

    var body: some View {
        VStack(spacing: 0) {
            overview
            if model.needsFullDiskAccess { fdaBanner }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    reclaimableSection
                    largestSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(.regularMaterial)
    }

    // MARK: Overview

    private var overview: some View {
        let cap = model.capacity
        let pct = cap.total == 0 ? 0 : Double(cap.used) / Double(cap.total) * 100
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                if model.phase == .scanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Scanning… \(Fmt.bytes(UInt64(max(0, model.progressBytes))))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Button {
                        model.rescan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Palette.tint(pct, red: 95, orange: 85).gradient)
                        .frame(width: max(4, geo.size.width * min(1, pct / 100)))
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(Fmt.bytes(UInt64(max(0, cap.used)))) of \(Fmt.bytes(UInt64(max(0, cap.total)))) used")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Fmt.bytes(UInt64(max(0, cap.free)))) free")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(cap.free < 10_737_418_240 ? .red : .secondary)
            }
            .monospacedDigit()
        }
        .padding(20)
        .padding(.top, 6)
    }

    private var fdaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("Some folders are hidden. Grant Full Disk Access for complete results.")
                .font(.system(size: 11))
            Spacer()
            Button("Open Settings") { model.openFullDiskAccessSettings() }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.orange.opacity(0.10))
    }

    // MARK: Reclaimable

    private var reclaimableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("RECLAIMABLE")
                Spacer()
                if model.reclaimableTotal > 0 {
                    Text("up to \(Fmt.bytes(UInt64(model.reclaimableTotal))) freeable")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            if model.reclaimables.isEmpty {
                PlaceholderRow(text: model.phase == .scanning ? "Looking for caches…" : "Nothing obvious to clear. Nice.")
            } else {
                VStack(spacing: 6) {
                    ForEach(model.reclaimables) { item in
                        ReclaimRow(item: item,
                                   cleaning: model.cleaning.contains(item.id)) {
                            model.clean(item)
                        }
                    }
                }
            }
        }
    }

    // MARK: Largest

    private var largestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("LARGEST IN HOME")

            if model.navStack.count > 1 {
                Breadcrumb(stack: model.navStack) { model.popTo($0) }
            }

            if let node = model.current {
                if node.children.isEmpty {
                    PlaceholderRow(text: "No large items here.")
                } else {
                    VStack(spacing: 2) {
                        ForEach(node.children) { child in
                            FileRow(node: child, totalDisk: model.capacity.total,
                                    onOpen: { model.drill(child) },
                                    onReveal: { model.reveal(child.url) })
                        }
                    }
                }
            } else {
                PlaceholderRow(text: "Scanning your home folder…")
            }
        }
    }
}

// MARK: - Rows

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
    }
}

private struct PlaceholderRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}

private struct ReclaimRow: View {
    let item: Reclaimable
    let cleaning: Bool
    var onAction: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(item.action == .reveal ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5, weight: .medium))
                Text(item.note).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if item.size > 0 {
                Text(Fmt.bytes(UInt64(item.size)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Group {
                if cleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: onAction) {
                        Text(actionLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .tint(item.action == .reveal ? .secondary : .accentColor)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
        )
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch item.action {
        case .delete: return "sparkles"
        case .emptyTrash: return "trash"
        case .deleteSnapshots: return "clock.badge.xmark"
        case .reveal: return "folder"
        }
    }
    private var actionLabel: String {
        switch item.action {
        case .delete: return "Clean"
        case .emptyTrash: return "Empty"
        case .deleteSnapshots: return "Delete"
        case .reveal: return "Reveal"
        }
    }
}

private struct FileRow: View {
    let node: DiskNode
    let totalDisk: Int64
    var onOpen: () -> Void
    var onReveal: () -> Void
    @State private var hovering = false

    private var fraction: Double {
        totalDisk == 0 ? 0 : Double(node.size) / Double(totalDisk)
    }

    var body: some View {
        HStack(spacing: 10) {
            if node.isAggregate {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15)).foregroundStyle(.tertiary).frame(width: 20)
            } else {
                Image(nsImage: IconLoader.icon(for: node.url.path))
                    .resizable().frame(width: 20, height: 20)
            }

            Text(node.name)
                .font(.system(size: 12.5))
                .foregroundStyle(node.isAggregate ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)

            Spacer(minLength: 8)

            // Share-of-disk bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.secondary)
                        .frame(width: max(2, geo.size.width * min(1, fraction)))
                }
            }
            .frame(width: 60, height: 4)

            Text(Fmt.bytes(UInt64(node.size)))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            if hovering && !node.isAggregate {
                Button(action: onReveal) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                }.buttonStyle(.borderless).help("Reveal in Finder")
            } else {
                Image(systemName: node.isDirectory && !node.isAggregate ? "chevron.right" : "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if node.isDirectory && !node.isAggregate { onOpen() }
        }
    }
}

private struct Breadcrumb: View {
    let stack: [DiskNode]
    var onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(stack.enumerated()), id: \.element.id) { idx, node in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Button { onTap(idx) } label: {
                    Text(node.name)
                        .font(.system(size: 11, weight: idx == stack.count - 1 ? .semibold : .regular))
                        .foregroundStyle(idx == stack.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
