import Foundation
import Darwin

/// One app's aggregated footprint. Helper processes (Electron renderers, etc.)
/// roll up under their owning .app, mirroring the Force Quit / Activity Monitor view.
struct ProcGroup: Identifiable {
    let id: String          // display name, also the group key
    var name: String
    var memoryBytes: UInt64
    var cpuPercent: Double  // sum across the group's processes (can exceed 100)
    var pids: [pid_t]
    var iconPath: String?   // .app bundle (or executable) path, for the app icon
}

/// Samples per-process memory (phys_footprint) + CPU via libproc.
/// CPU is delta-based, so the first sample reports 0% CPU.
final class ProcessSampler {
    private var prevCPUTime: [pid_t: UInt64] = [:]   // pid -> cumulative ns
    private var prevTimestamp: UInt64 = 0            // mach uptime ns

    func sample(limit: Int = 8) -> [ProcGroup] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = prevTimestamp == 0 ? 0 : (now > prevTimestamp ? now - prevTimestamp : 0)

        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 16)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var groups: [String: ProcGroup] = [:]
        var newCPUTime: [pid_t: UInt64] = [:]

        for idx in 0..<Int(filled) {
            let pid = pids[idx]
            guard pid > 0 else { continue }

            var rusage = rusage_info_v2()
            let r = withUnsafeMutablePointer(to: &rusage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { ptr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, ptr)
                }
            }
            guard r == 0 else { continue }   // typically a root-owned process; skip

            let footprint = rusage.ri_phys_footprint
            let cpuTime = rusage.ri_user_time + rusage.ri_system_time
            newCPUTime[pid] = cpuTime

            var cpuPercent = 0.0
            if elapsed > 0, let prev = prevCPUTime[pid], cpuTime >= prev {
                cpuPercent = Double(cpuTime - prev) / Double(elapsed) * 100
            }

            let resolved = resolve(pid: pid)
            if var existing = groups[resolved.name] {
                existing.memoryBytes += footprint
                existing.cpuPercent += cpuPercent
                existing.pids.append(pid)
                if existing.iconPath == nil { existing.iconPath = resolved.iconPath }
                groups[resolved.name] = existing
            } else {
                groups[resolved.name] = ProcGroup(id: resolved.name, name: resolved.name,
                                                  memoryBytes: footprint,
                                                  cpuPercent: cpuPercent, pids: [pid],
                                                  iconPath: resolved.iconPath)
            }
        }

        prevCPUTime = newCPUTime
        prevTimestamp = now

        return groups.values
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Sends a signal to every process in the group. SIGTERM by default,
    /// SIGKILL when `force` is true. Returns the number of pids signalled OK.
    @discardableResult
    func kill(_ group: ProcGroup, force: Bool) -> Int {
        let sig = force ? SIGKILL : SIGTERM
        var ok = 0
        for pid in group.pids where pid > 0 {
            if Darwin.kill(pid, sig) == 0 { ok += 1 }
        }
        return ok
    }

    // MARK: Naming

    /// Resolves a pid to a friendly app name + an icon source path. Groups
    /// Electron-style helper processes under their top-level .app (first ".app"
    /// in the exec path); falls back to the executable basename for daemons.
    private func resolve(pid: pid_t) -> (name: String, iconPath: String?) {
        var pathBuf = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        guard len > 0 else { return ("pid \(pid)", nil) }
        let path = String(cString: pathBuf)

        // Prefer the outermost ".app" bundle name (rolls up helper processes).
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.upperBound].dropLast()) // ".../Foo.app"
            let name = (String(path[..<range.lowerBound]) as NSString).lastPathComponent
            if !name.isEmpty { return (name, bundlePath) }
        }
        let base = (path as NSString).lastPathComponent
        return (base.isEmpty ? "pid \(pid)" : base, path)
    }
}
