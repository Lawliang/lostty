#if os(macOS)
import Darwin
import Foundation

/// One client attached over SSH: its tmux client's pid and its session.
/// A phone that reconnects is a new client, even on the same session.
struct AttachedClient: Hashable, Sendable {
    var pid: Int32
    var session: String
}

/// Sessions a client attached to over SSH right now: the phone, or any
/// other SSH login. They can't be told apart, so the menu never names a phone.
enum AttachedPhones {
    static let listFormat = "#{client_pid}\t#{session_name}"

    static func current() -> [String] {
        guard let out = TmuxClient().run(["list-clients", "-F", listFormat]) else { return [] }
        return sessions(clients: out, parent: processParent)
    }

    static let idFormat = "#{client_pid}\t#{session_id}"

    /// Each SSH client and the session id ("$3") it is on.
    static func currentClients() -> [AttachedClient] {
        guard let out = TmuxClient().run(["list-clients", "-F", idFormat]) else { return [] }
        return clients(out, parent: processParent)
    }

    /// `list-clients` output (`listFormat` or `idFormat`): the clients
    /// that came through SSH.
    static func clients(_ output: String, parent: (Int32) -> (ppid: Int32, name: String)?) -> [AttachedClient] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, let pid = Int32(fields[0]), cameThroughSSH(pid, parent: parent) else { return nil }
            return AttachedClient(pid: pid, session: String(fields[1]))
        }
    }

    static func sessions(clients output: String, parent: (Int32) -> (ppid: Int32, name: String)?) -> [String] {
        Set(clients(output, parent: parent).map(\.session)).sorted()
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
