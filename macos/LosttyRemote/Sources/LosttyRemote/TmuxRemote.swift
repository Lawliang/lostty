import Foundation

/// What the Mac says a session's Claude is doing (`@lostty_claude`).
public enum ClaudeActivity: String, Sendable {
    case waiting
    case working
}

/// A session on the Mac's Lostty tmux (`tmux -L lostty`).
public struct RemoteSession: Equatable, Sendable {
    public var id: String
    public var name: String
    /// The Mac pane showing it, if any.
    public var surface: String?
    /// The Mac Lostty's pid, if a Mac window shows it.
    public var owner: Int32?
    /// The name typed on the Mac (Rename Tab…) or the phone (Rename).
    public var label: String?
    /// Set by the Mac for sessions it shows; nil otherwise.
    public var claude: ClaudeActivity?
    /// `#{pane_title}`: Claude Code's task, or a shell's folder.
    public var title: String
    /// `#{pane_current_path}`: the running program's folder.
    public var path: String
    /// `#{pane_current_command}`; Claude Code reports its version ("2.1.296").
    public var command: String
    /// `#{session_activity}`: last use.
    public var activity: Date?

    public init(
        id: String, name: String, surface: String?, owner: Int32?, label: String? = nil,
        claude: ClaudeActivity? = nil, title: String = "", path: String = "", command: String = "",
        activity: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.surface = surface
        self.owner = owner
        self.label = label
        self.claude = claude
        self.title = title
        self.path = path
        self.command = command
        self.activity = activity
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

    /// The name typed on the Mac or the phone.
    public static let labelOption = "@lostty_label"
    /// "waiting" or "working", written by the Mac.
    public static let claudeOption = "@lostty_claude"

    /// id, name, Mac pane, Mac Lostty pid, label, Claude state, last use,
    /// command, folder, title — tab separated. The title goes last: any
    /// program sets it, so a tab inside it stays inside it.
    public static let listFormat = [
        "#{session_id}", "#{session_name}", "#{@lostty_surface}", "#{@lostty_owner}",
        "#{\(labelOption)}", "#{\(claudeOption)}", "#{session_activity}",
        "#{pane_current_command}", "#{pane_current_path}", "#{pane_title}",
    ].joined(separator: "\t")

    /// SSH commands have no locale, and without UTF-8 tmux turns the tab
    /// separators into `_`, so `-u` keeps them.
    public static var listCommand: String {
        "\(pathPrefix) tmux -u -L lostty list-sessions -F \(shellQuote(listFormat))"
    }

    /// The command the PTY's shell replaces itself with. `-u` and LANG keep
    /// tmux in UTF-8 when the SSH session has no locale. TERMINFO, when
    /// given, lets tmux find xterm-ghostty; otherwise ncurses finds it in
    /// ~/.terminfo. `-f /dev/null`: attach-session starts a server when
    /// none runs, and the viewer must never start one (it would read
    /// ~/.tmux.conf); a server started this way has no sessions and exits.
    ///
    /// Ids restart at $0 when the Mac's tmux server restarts, so an id alone
    /// can name a different session than the one listed: the command first
    /// checks the session's name and exits 1 if it differs.
    public static func attachCommand(sessionID: String, name: String, terminfoDir: String?) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        // TERMINFO goes first: the shell's TERM is xterm-ghostty, and the
        // guard's tmux fails on an unknown terminal without it.
        let export = terminfoDir.map { "export TERMINFO=\(shellQuote($0)); " } ?? ""
        return export + nameGuard(sessionID: sessionID, name: name)
            + "exec env LANG=\"${LANG:-en_US.UTF-8}\" \(pathPrefix) tmux -u -L lostty -f /dev/null attach-session -t \(shellQuote(sessionID))"
    }

    /// Ends session `sessionID` (and with it the Mac window showing it).
    /// Exits 1 (without killing) if the id now names a different session.
    public static func killCommand(sessionID: String, name: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return nameGuard(sessionID: sessionID, name: name) + "\(pathPrefix) tmux -u -L lostty kill-session -t \(shellQuote(sessionID))"
    }

    /// `-f /dev/null`: display-message must not start a server either.
    private static func nameGuard(sessionID: String, name: String) -> String {
        "[ \"$(\(pathPrefix) tmux -u -L lostty -f /dev/null display-message -p -t \(shellQuote(sessionID)) "
            + "'#{session_name}' 2>/dev/null)\" = \(shellQuote(name)) ] || exit 1; "
    }

    public static func parse(_ output: String) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 9, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 10, isSessionID(f[0]) else { return nil }
            return RemoteSession(
                id: f[0],
                name: f[1],
                surface: f[2].isEmpty ? nil : f[2],
                owner: Int32(f[3]),
                label: f[4].isEmpty ? nil : f[4],
                claude: ClaudeActivity(rawValue: f[5]),
                title: f[9],
                path: f[8],
                command: f[7],
                activity: TimeInterval(f[6]).map { Date(timeIntervalSince1970: $0) })
        }
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isSessionID(_ s: String) -> Bool {
        s.count >= 2 && s.first == "$" && s.dropFirst().allSatisfy(\.isASCII) && s.dropFirst().allSatisfy(\.isNumber)
    }
}

extension RemoteSession {
    /// The order the session list shows: by project name, as Finder sorts.
    public static func forPicking(_ sessions: [RemoteSession]) -> [RemoteSession] {
        sessions.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
