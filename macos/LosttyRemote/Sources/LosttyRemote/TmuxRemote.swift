import Foundation

/// A session on the Mac's Lostty tmux (`tmux -L lostty`).
public struct RemoteSession: Equatable, Sendable {
    public var id: String
    public var name: String
    /// The Mac pane showing it, if any.
    public var surface: String?
    /// The Mac Lostty's pid, if a Mac window shows it.
    public var owner: Int32?

    public init(id: String, name: String, surface: String?, owner: Int32?) {
        self.id = id
        self.name = name
        self.surface = surface
        self.owner = owner
    }
}

public enum TmuxRemoteError: Error, Equatable {
    case badSessionID(String)
}

/// Shell commands run over SSH against the Mac's Lostty tmux, and parsing
/// their output. Sessions are always targeted by id ("$3"), never by name
/// (tmux prefix-matches names), and attach never passes -d (that would close
/// the Mac window, which ends the session).
public enum TmuxRemote {
    /// SSH commands get a minimal PATH; tmux is usually in Homebrew's.
    public static let pathPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"

    /// id, name, Mac pane, Mac Lostty pid — tab separated.
    public static let listFormat = "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}"

    /// SSH commands have no locale, and without UTF-8 tmux turns the tab
    /// separators into `_`, so `-u` keeps them.
    public static var listCommand: String {
        "\(pathPrefix) tmux -u -L lostty list-sessions -F \(shellQuote(listFormat))"
    }

    /// The command the PTY's shell replaces itself with. `-u` and LANG keep
    /// tmux in UTF-8 when the SSH session has no locale; TERMINFO lets tmux
    /// find xterm-ghostty. `-f /dev/null`: attach-session starts a server when
    /// none runs, and the viewer must never start one (it would read
    /// ~/.tmux.conf); a server started this way has no sessions and exits.
    public static func attachCommand(sessionID: String, terminfoDir: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return "exec env LANG=\"${LANG:-en_US.UTF-8}\" TERMINFO=\(shellQuote(terminfoDir)) "
            + "\(pathPrefix) tmux -u -L lostty -f /dev/null attach-session -t \(shellQuote(sessionID))"
    }

    public static func parse(_ output: String) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, isSessionID(fields[0]) else { return nil }
            return RemoteSession(
                id: fields[0],
                name: fields[1],
                surface: fields[2].isEmpty ? nil : fields[2],
                owner: Int32(fields[3]))
        }
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isSessionID(_ s: String) -> Bool {
        s.count >= 2 && s.first == "$" && s.dropFirst().allSatisfy(\.isASCII) && s.dropFirst().allSatisfy(\.isNumber)
    }
}
