#if os(macOS)
import Darwin
import Foundation

/// Sessions a client attached to over SSH right now: the phone, or any
/// other SSH login. They can't be told apart, so the menu never names a phone.
enum AttachedPhones {
    static let listFormat = "#{client_pid}\t#{session_name}"

    static func current() -> [String] {
        guard let out = TmuxClient().run(["list-clients", "-F", listFormat]) else { return [] }
        return sessions(clients: out, parent: processParent)
    }

    static func sessions(clients: String, parent: (Int32) -> (ppid: Int32, name: String)?) -> [String] {
        var names = Set<String>()
        for line in clients.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            if cameThroughSSH(pid, parent: parent) { names.insert(String(fields[1])) }
        }
        return names.sorted()
    }

    /// Walks up at most 10 parents looking for sshd (or sshd-session).
    private static func cameThroughSSH(_ pid: Int32, parent: (Int32) -> (ppid: Int32, name: String)?) -> Bool {
        var current = pid
        for _ in 0..<10 {
            guard current > 1, let info = parent(current) else { return false }
            if info.name.hasPrefix("sshd") { return true }
            current = info.ppid
        }
        return false
    }

    private static func processParent(_ pid: Int32) -> (ppid: Int32, name: String)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (info.kp_eproc.e_ppid, name)
    }
}
#endif
