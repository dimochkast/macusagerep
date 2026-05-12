#if canImport(AppKit)
import Foundation
import AppKit
import Darwin

public final class ResourceSampler {
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousSampleTime: Date?
    private let nsPerTick: Double

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        self.nsPerTick = tb.denom > 0 ? Double(tb.numer) / Double(tb.denom) : 1.0
    }

    public func sample(now: Date = Date(), excluded: Set<String> = []) -> [ResourceSample] {
        let pids = Self.allPids()
        let wallDelta = previousSampleTime.map { now.timeIntervalSince($0) } ?? 0

        struct Agg { var name: String; var cpuDeltaNs: UInt64; var mem: Int64; var present: Bool }
        var groups: [String: Agg] = [:]
        var currentCPU: [pid_t: UInt64] = [:]

        for pid in pids where pid > 0 {
            guard let info = Self.taskInfo(for: pid) else { continue }
            let cpuNs = info.pti_total_user &+ info.pti_total_system
            currentCPU[pid] = cpuNs

            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  !bundleID.isEmpty
            else { continue }
            if excluded.contains(bundleID) { continue }

            let name = app.localizedName ?? bundleID
            let prev = previousCPU[pid]
            let deltaNs: UInt64
            if let prev, cpuNs >= prev {
                deltaNs = cpuNs - prev
            } else {
                deltaNs = 0 // first sample for this pid, or counter wrap
            }

            var g = groups[bundleID] ?? Agg(name: name, cpuDeltaNs: 0, mem: 0, present: false)
            g.cpuDeltaNs &+= deltaNs
            g.mem += Int64(info.pti_resident_size)
            g.present = true
            groups[bundleID] = g
        }

        previousCPU = currentCPU
        previousSampleTime = now

        guard wallDelta > 0 else { return [] }

        return groups.compactMap { bundleID, agg in
            guard agg.present else { return nil }
            let cpuSeconds = Double(agg.cpuDeltaNs) * nsPerTick / 1e9
            let cpuPercent = cpuSeconds / wallDelta * 100.0
            return ResourceSample(
                timestamp: now,
                bundleID: bundleID,
                appName: agg.name,
                cpuPercent: cpuPercent,
                memoryBytes: agg.mem
            )
        }
    }

    private static func allPids() -> [pid_t] {
        let size = proc_listallpids(nil, 0)
        guard size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytes = Int32(capacity * MemoryLayout<pid_t>.size)
        let written = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listallpids(buf.baseAddress, bytes)
        }
        guard written > 0 else { return [] }
        let count = Int(written) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count))
    }

    private static func taskInfo(for pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, size)
        }
        return got == size ? info : nil
    }
}
#endif
