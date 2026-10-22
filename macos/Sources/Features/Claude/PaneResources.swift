#if os(macOS)
import Darwin
import Foundation

/// What runs in a pane uses: its CPU, as a percent of one core (two busy
/// cores read 200%), and its memory footprint (Activity Monitor's
/// "Memory").
struct PaneResources: Equatable {
    var cpu: Double
    var memory: UInt64
}

/// Samples the processes in the panes the bottom bars show. Each bar
/// watches its focused pane while it's on screen; one timer and one
/// background queue serve them all, and the timer stops when no bar
/// watches.
@MainActor
final class PaneResourceMonitor: ObservableObject {
    static let shared = PaneResourceMonitor()
    static let interval: TimeInterval = 2

    /// Only panes sampled twice: the CPU needs two readings.
    @Published private(set) var resources: [UUID: PaneResources] = [:]

    private var watchers: [UUID: Int] = [:]
    private var timer: Timer?
    private var changed: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.lawliang.lostty.pane-resources", qos: .utility)
    private let sampler = PaneResourceSampler(owner: ProcessInfo.processInfo.processIdentifier)

    func watch(_ pane: UUID) {
        watchers[pane, default: 0] += 1
        guard watchers[pane] == 1 else { return }
        start()
        // A first reading now and the second soon, so a newly focused pane
        // doesn't wait a whole interval for its CPU.
        sample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func unwatch(_ pane: UUID) {
        guard let count = watchers[pane] else { return }
        if count > 1 {
            watchers[pane] = count - 1
            return
        }
        watchers[pane] = nil
        resources[pane] = nil
        if watchers.isEmpty { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = Self.interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // New panes show up in tmux; look them up again.
        changed = NotificationCenter.default.addObserver(
            forName: .losttySessionsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let sampler = self.sampler
                self.queue.async { sampler.forgetPanes() }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let changed { NotificationCenter.default.removeObserver(changed) }
        changed = nil
    }

    private func sample() {
        let panes = Set(watchers.keys)
        guard !panes.isEmpty else { return }
        let sampler = self.sampler
        queue.async {
            let sampled = sampler.sample(panes)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let current = sampled.filter { self.watchers[$0.key] != nil }
                    if current != self.resources { self.resources = current }
                }
            }
        }
    }
}

/// The process work behind `PaneResourceMonitor`, on its queue only. A
/// pane's processes are its tmux pane's shell (`#{pane_pid}`) and
/// everything under it; panes not on Lostty's tmux have none.
final class PaneResourceSampler: @unchecked Sendable {
    static let paneFormat = "#{@lostty_surface}\t#{@lostty_owner}\t#{pane_pid}"
    /// How long a pane tmux didn't list waits before it's looked up again.
    static let retry: TimeInterval = 10

    private let owner: Int32
    private let client = TmuxClient()
    private var shells: [UUID: [pid_t]] = [:]
    private var missedAt: Date?
    /// Each pane's last reading: when, and each process's CPU time.
    private var previous: [UUID: (at: UInt64, cpu: [pid_t: UInt64])] = [:]

    init(owner: Int32) {
        self.owner = owner
    }

    func forgetPanes() {
        shells = [:]
        missedAt = nil
    }

    /// The panes read twice or more.
    func sample(_ panes: Set<UUID>) -> [UUID: PaneResources] {
        lookUp(panes)
        previous = previous.filter { panes.contains($0.key) }
        var result: [UUID: PaneResources] = [:]
        for pane in panes {
            guard let roots = shells[pane] else { continue }
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            var cpu: [pid_t: UInt64] = [:]
            var memory: UInt64 = 0
            for pid in Self.tree(roots) {
                guard let usage = Self.usage(pid) else { continue }
                cpu[pid] = usage.cpu
                memory += usage.memory
            }
            if let last = previous[pane] {
                let percent = PaneResourceMath.cpuPercent(previous: last.cpu, current: cpu, elapsed: now - last.at)
                result[pane] = PaneResources(cpu: percent, memory: memory)
            }
            previous[pane] = (now, cpu)
        }
        return result
    }

    /// Asks tmux for the panes' shells when one is missing or has exited,
    /// but not again for `retry` after a pane wasn't there.
    private func lookUp(_ panes: Set<UUID>) {
        let missing = panes.contains { pane in
            shells[pane].map { !$0.allSatisfy(ProcessLiveness.isAlive) } ?? true
        }
        guard missing else { return }
        if let missedAt, Date().timeIntervalSince(missedAt) < Self.retry { return }
        guard let output = client.run(["list-panes", "-a", "-F", Self.paneFormat]) else {
            missedAt = Date()
            return
        }
        shells = Self.shells(output, owner: owner)
        missedAt = panes.allSatisfy { shells[$0] != nil } ? nil : Date()
    }

    /// Parses `list-panes -a -F paneFormat`: pane → its shells, for the
    /// panes Lostty `owner` shows.
    static func shells(_ output: String, owner: Int32) -> [UUID: [pid_t]] {
        var result: [UUID: [pid_t]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, let pane = UUID(uuidString: f[0]), Int32(f[1]) == owner,
                  let pid = pid_t(f[2]), pid > 0 else { continue }
            result[pane, default: []].append(pid)
        }
        return result
    }

    /// `roots` and every process under them.
    static func tree(_ roots: [pid_t]) -> [pid_t] {
        var result: [pid_t] = []
        var pending = roots
        while let pid = pending.popLast(), result.count < 4096 {
            result.append(pid)
            pending += children(pid)
        }
        return result
    }

    private static func children(_ pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer,
                                  Int32(buffer.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return [] }
        return buffer.prefix(Int(bytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// A process's CPU time in nanoseconds and its memory footprint; nil
    /// when it's gone or not ours to read.
    static func usage(_ pid: pid_t) -> (cpu: UInt64, memory: UInt64)? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return nil }
        // In Mach time units, not nanoseconds, on Apple silicon.
        let ticks = info.ri_user_time + info.ri_system_time
        let cpu = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
        return (cpu, info.ri_phys_footprint)
    }
}

enum PaneResourceMath {
    /// CPU used between two readings as a percent of one core. A process
    /// that started since counts all its time; one that ended, none.
    static func cpuPercent(previous: [pid_t: UInt64], current: [pid_t: UInt64], elapsed: UInt64) -> Double {
        guard elapsed > 0 else { return 0 }
        let used = current.reduce(UInt64(0)) { sum, entry in
            let before = previous[entry.key] ?? 0
            return sum + (entry.value > before ? entry.value - before : 0)
        }
        return Double(used) / Double(elapsed) * 100
    }

    /// "340M" under a gigabyte, then "1.2G".
    static func memory(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        if mib < 999.5 { return "\(Int(mib.rounded()))M" }
        return String(format: "%.1fG", mib / 1024)
    }
}
#endif
