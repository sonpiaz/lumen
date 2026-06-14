import Foundation
import Darwin

/// A single snapshot of whole-machine resource usage.
struct SystemStats {
    var cpuPercent: Double          // 0...100, normalized across all cores
    var ramUsedBytes: UInt64
    var ramTotalBytes: UInt64
    var diskUsedBytes: UInt64
    var diskTotalBytes: UInt64

    var ramPercent: Double {
        ramTotalBytes == 0 ? 0 : Double(ramUsedBytes) / Double(ramTotalBytes) * 100
    }
    var diskPercent: Double {
        diskTotalBytes == 0 ? 0 : Double(diskUsedBytes) / Double(diskTotalBytes) * 100
    }

    static let zero = SystemStats(cpuPercent: 0, ramUsedBytes: 0, ramTotalBytes: 0,
                                  diskUsedBytes: 0, diskTotalBytes: 0)
}

/// Samples CPU / RAM / disk straight from Mach + the filesystem.
/// No subprocesses, no polling daemons — the lightest path on macOS.
final class SystemSampler {
    // Previous CPU tick totals, for delta-based utilization.
    private var prevBusy: UInt64 = 0
    private var prevTotal: UInt64 = 0
    private let totalRAM = ProcessInfo.processInfo.physicalMemory

    func sample() -> SystemStats {
        SystemStats(
            cpuPercent: cpuUsage(),
            ramUsedBytes: ramUsed(),
            ramTotalBytes: totalRAM,
            diskUsedBytes: diskUsed().used,
            diskTotalBytes: diskUsed().total
        )
    }

    // MARK: CPU

    private func cpuUsage() -> Double {
        var cpuCount: natural_t = 0
        var infoPtr: processor_info_array_t!
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &infoPtr, &infoCount)
        guard result == KERN_SUCCESS, let info = infoPtr else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let base = i * states
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let sys  = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            busy += user + sys + nice
            total += user + sys + nice + idle
        }

        let busyDelta = busy >= prevBusy ? busy - prevBusy : 0
        let totalDelta = total >= prevTotal ? total - prevTotal : 0
        prevBusy = busy
        prevTotal = total

        guard totalDelta > 0 else { return 0 }
        return min(100, Double(busyDelta) / Double(totalDelta) * 100)
    }

    // MARK: RAM

    /// "Memory Used" approximation matching Activity Monitor:
    /// App Memory (internal anonymous, minus purgeable) + Wired + Compressed.
    private func ramUsed() -> UInt64 {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride /
                                          MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)

        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeable = UInt64(vmStats.purgeable_count)
        let appPages = internalPages >= purgeable ? internalPages - purgeable : 0
        let wired = UInt64(vmStats.wire_count)
        let compressed = UInt64(vmStats.compressor_page_count)

        return (appPages + wired + compressed) * ps
    }

    // MARK: Disk

    private func diskUsed() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage
        else { return (0, 0) }

        let totalBytes = UInt64(total)
        let availBytes = UInt64(max(0, available))
        let used = totalBytes >= availBytes ? totalBytes - availBytes : 0
        return (used, totalBytes)
    }
}
