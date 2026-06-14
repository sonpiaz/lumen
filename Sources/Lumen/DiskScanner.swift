import Foundation

/// A node in the scanned disk tree. Only "significant" children are kept; the
/// rest fold into a single aggregate row so the tree stays small in memory.
final class DiskNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let isAggregate: Bool   // synthetic "N smaller items" row
    let children: [DiskNode]

    init(url: URL, name: String, isDirectory: Bool, size: Int64,
         isAggregate: Bool = false, children: [DiskNode] = []) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.isAggregate = isAggregate
        self.children = children
    }
}

/// A space hog that's safe (or safe-ish) to reclaim.
struct Reclaimable: Identifiable {
    enum Action { case delete, emptyTrash, deleteSnapshots, reveal }
    let id: String
    let title: String
    let note: String
    let url: URL?
    var size: Int64
    let action: Action
    var snapshotDates: [String] = []
}

/// On-demand disk usage scanner. Reads file sizes via the filesystem; nothing
/// runs unless a scan is explicitly started (keeps the app idle-cheap).
final class DiskScanner {
    var isCancelled = false

    private let lock = NSLock()
    private var _bytes: Int64 = 0
    private var _permissionError = false
    private var _nodeModulesBytes: Int64 = 0
    private var _nodeModulesCount = 0

    private static let keepThreshold: Int64 = 20 * 1024 * 1024  // 20 MB

    var bytesScanned: Int64 { lock.lock(); defer { lock.unlock() }; return _bytes }
    var hadPermissionError: Bool { lock.lock(); defer { lock.unlock() }; return _permissionError }

    private func addBytes(_ n: Int64) { lock.lock(); _bytes += n; lock.unlock() }
    private func flagPermission() { lock.lock(); _permissionError = true; lock.unlock() }
    private func addNodeModules(_ n: Int64) {
        lock.lock(); _nodeModulesBytes += n; _nodeModulesCount += 1; lock.unlock()
    }

    // MARK: Disk capacity

    func capacity() -> (used: Int64, total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = v.volumeTotalCapacity,
        let free = v.volumeAvailableCapacityForImportantUsage else { return (0, 0, 0) }
        let t = Int64(total), f = Int64(max(0, free))
        return (max(0, t - f), t, f)
    }

    // MARK: Home tree

    func scanHome() -> DiskNode {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let level1 = childrenURLs(home)

        // To use all cores, parallelize at the *second* level: one heavy top
        // folder (e.g. Library) is split into its children across cores instead
        // of running on a single thread. Work units are flattened (no nested
        // concurrentPerform, which would oversubscribe the thread pool).
        let isDir = level1.map { directoryNonSymlink($0) }
        var level2: [[URL]] = Array(repeating: [], count: level1.count)
        for (i, url) in level1.enumerated() where isDir[i] {
            level2[i] = childrenURLs(url)
        }

        var work: [(owner: Int, url: URL)] = []
        for (i, url) in level1.enumerated() {
            if isDir[i] {
                for child in level2[i] { work.append((i, child)) }
            } else {
                work.append((i, url))
            }
        }

        var wresults = [DiskNode?](repeating: nil, count: work.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: work.count) { k in
            if self.isCancelled { return }
            let node = self.walk(work[k].url, keepChildren: true)
            lock.lock(); wresults[k] = node; lock.unlock()
        }

        // Reassemble: group each owner's level-2 nodes back under its folder.
        var kidsByOwner: [[DiskNode]] = Array(repeating: [], count: level1.count)
        var fileByOwner: [Int: DiskNode] = [:]
        for (k, item) in work.enumerated() {
            guard let node = wresults[k] else { continue }
            if isDir[item.owner] { kidsByOwner[item.owner].append(node) }
            else { fileByOwner[item.owner] = node }
        }

        var level1Nodes: [DiskNode] = []
        for (i, url) in level1.enumerated() {
            if isDir[i] {
                let kids = kidsByOwner[i]
                let total = kids.reduce(0) { $0 + $1.size }
                level1Nodes.append(DiskNode(url: url, name: url.lastPathComponent,
                                            isDirectory: true, size: total,
                                            children: prune(kids, parent: url)))
            } else if let f = fileByOwner[i] {
                level1Nodes.append(f)
            }
        }

        let children = level1Nodes.sorted { $0.size > $1.size }
        let total = children.reduce(0) { $0 + $1.size }
        return DiskNode(url: home, name: "Home", isDirectory: true,
                        size: total, children: children)
    }

    private func childrenURLs(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [])) ?? []
    }

    private func directoryNonSymlink(_ url: URL) -> Bool {
        guard let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rv.isSymbolicLink != true else { return false }
        return rv.isDirectory == true
    }

    private func walk(_ url: URL, keepChildren: Bool) -> DiskNode? {
        if isCancelled { return nil }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }
        if rv.isSymbolicLink == true { return nil }   // don't follow / double-count

        guard rv.isDirectory == true else {
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            addBytes(size)
            return DiskNode(url: url, name: url.lastPathComponent,
                            isDirectory: false, size: size)
        }

        let isNodeModules = url.lastPathComponent == "node_modules"
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys), options: [])
        } catch {
            flagPermission()
            return DiskNode(url: url, name: url.lastPathComponent,
                            isDirectory: true, size: 0)
        }

        // Inside node_modules we still sum bytes but stop building tree nodes.
        let keepHere = keepChildren && !isNodeModules
        var total: Int64 = 0
        var childNodes: [DiskNode] = []
        for child in contents {
            guard let node = walk(child, keepChildren: keepHere) else { continue }
            total += node.size
            if keepHere { childNodes.append(node) }
        }
        if isNodeModules { addNodeModules(total) }

        return DiskNode(url: url, name: url.lastPathComponent,
                        isDirectory: true, size: total,
                        children: keepHere ? prune(childNodes, parent: url) : [])
    }

    private func prune(_ nodes: [DiskNode], parent: URL) -> [DiskNode] {
        let sorted = nodes.sorted { $0.size > $1.size }
        var kept = sorted.filter { $0.size >= Self.keepThreshold }
        let small = sorted.filter { $0.size < Self.keepThreshold }
        let sum = small.reduce(0) { $0 + $1.size }
        if sum > 0 {
            kept.append(DiskNode(url: parent, name: "\(small.count) smaller items",
                                 isDirectory: false, size: sum, isAggregate: true))
        }
        return kept
    }

    // MARK: Reclaimables

    func nodeModulesSummary() -> Reclaimable? {
        lock.lock(); let bytes = _nodeModulesBytes; let count = _nodeModulesCount; lock.unlock()
        guard bytes > 0 else { return nil }
        return Reclaimable(
            id: "node_modules",
            title: "node_modules (\(count) folders)",
            note: "Delete per-project with `rm -rf` when idle; `npm install` restores",
            url: FileManager.default.homeDirectoryForCurrentUser,
            size: bytes, action: .reveal)
    }

    func computeReclaimables() -> [Reclaimable] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func p(_ rel: String) -> URL { home.appendingPathComponent(rel) }

        // (id, title, note, path, action) — sized concurrently below.
        let targets: [(String, String, String, URL, Reclaimable.Action)] = [
            ("caches", "App caches", "Apps rebuild caches as needed",
             p("Library/Caches"), .delete),
            ("dotcache", "Dev & model caches (~/.cache)", "Re-downloaded when needed (incl. Hugging Face)",
             p(".cache"), .delete),
            ("derived", "Xcode DerivedData", "Rebuilt automatically on next build",
             p("Library/Developer/Xcode/DerivedData"), .delete),
            ("devicesupport", "iOS DeviceSupport", "Re-downloaded when you attach a device",
             p("Library/Developer/Xcode/iOS DeviceSupport"), .delete),
            ("simcache", "Simulator caches", "Regenerated by Xcode",
             p("Library/Developer/CoreSimulator/Caches"), .delete),
            ("npm", "npm cache", "Restored by the next install",
             p(".npm/_cacache"), .delete),
            ("pnpm", "pnpm store", "Restored by the next install",
             p("Library/pnpm/store"), .delete),
            ("trash", "Trash", "Permanently removes trashed items",
             home.appendingPathComponent(".Trash"), .emptyTrash),
            ("archives", "Xcode Archives", "Your shipped builds — review before removing",
             p("Library/Developer/Xcode/Archives"), .reveal),
            ("docker", "Docker data", "Use `docker system prune` instead of deleting",
             p("Library/Containers/com.docker.docker/Data"), .reveal),
        ]

        var sized = [Reclaimable?](repeating: nil, count: targets.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: targets.count) { i in
            if self.isCancelled { return }
            let t = targets[i]
            let size = self.directorySize(t.3)
            if size > 0 {
                let r = Reclaimable(id: t.0, title: t.1, note: t.2, url: t.3,
                                    size: size, action: t.4)
                lock.lock(); sized[i] = r; lock.unlock()
            }
        }
        var items = sized.compactMap { $0 }

        // APFS local snapshots — the usual culprit behind a bloated "System Data".
        let snaps = localSnapshotDates()
        if !snaps.isEmpty {
            items.append(Reclaimable(
                id: "snapshots",
                title: "Time Machine local snapshots (\(snaps.count))",
                note: "Hidden copies macOS keeps on disk — often frees the 'missing' space",
                url: nil, size: 0, action: .deleteSnapshots, snapshotDates: snaps))
        }

        return items.sorted { $0.size > $1.size }
    }

    /// Recursive byte total for a single path — fast, no tree.
    func directorySize(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if isCancelled { break }
            guard let rv = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  rv.isRegularFile == true else { continue }
            total += Int64(rv.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Date tokens of local Time Machine snapshots, e.g. "2026-06-14-120000".
    func localSnapshotDates() -> [String] {
        let out = runTmutil(["listlocalsnapshots", "/"])
        return out.split(separator: "\n").compactMap { line in
            guard line.contains("com.apple.TimeMachine.") else { return nil }
            return line.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                .replacingOccurrences(of: ".local", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    @discardableResult
    func runTmutil(_ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
