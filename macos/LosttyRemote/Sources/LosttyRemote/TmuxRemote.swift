import Foundation

/// What the Mac says a session's Claude is doing (`@lostty_claude`).
/// `subagents`: Claude finished its turn but its subagents still work (the
/// Mac's trace bounces along the bottom edge then); it counts as working.
public enum ClaudeActivity: String, Sendable {
    case waiting
    case working
    case subagents = "agents"

    /// Working, by Claude or only its subagents.
    public var isWorking: Bool { self != .waiting }
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
    /// What its Claude is doing while it works or waits ("Editing
    /// Foo.swift"), set by the Mac; nil otherwise.
    public var action: String?
    /// Claude's working line in the pane, read while it works.
    public var spinner: ClaudeSpinner?
    /// `#{pane_title}`: Claude Code's task, or a shell's folder.
    public var title: String
    /// `#{pane_current_path}`: the running program's folder.
    public var path: String
    /// `#{pane_current_command}`; Claude Code reports its version ("2.1.296").
    public var command: String
    /// `#{session_activity}`: last use.
    public var activity: Date?
    /// The look of the Mac pane showing it (`@lostty_skin`), if it has one.
    public var skin: SessionSkin?
    /// Its Claude's context window (`@lostty_context`), while Claude runs there.
    public var context: SessionContext?
    /// The folder of the git repo `path` is in (the main checkout's, for a
    /// linked worktree); nil outside git or when the listing didn't say.
    public var repo: String?
    /// The branch checked out at `path`; nil when detached or outside git.
    public var branch: String?

    public init(
        id: String, name: String, surface: String?, owner: Int32?, label: String? = nil,
        claude: ClaudeActivity? = nil, action: String? = nil, spinner: ClaudeSpinner? = nil, title: String = "",
        path: String = "", command: String = "", activity: Date? = nil, skin: SessionSkin? = nil,
        context: SessionContext? = nil, repo: String? = nil, branch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.surface = surface
        self.owner = owner
        self.label = label
        self.claude = claude
        self.action = action
        self.spinner = spinner
        self.title = title
        self.path = path
        self.command = command
        self.activity = activity
        self.skin = skin
        self.context = context
        self.repo = repo
        self.branch = branch
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
    /// The pane's skin colors (`SessionSkin.encoded`), written by the Mac.
    public static let skinOption = "@lostty_skin"
    /// What its Claude is doing, one line, written by the Mac.
    public static let actionOption = "@lostty_action"
    /// Its Claude's context window (`SessionContext.encoded`), written by the Mac.
    public static let contextOption = "@lostty_context"

    /// id, name, Mac pane, Mac Lostty pid, label, Claude state, last use,
    /// command, folder, skin, Claude's action, Claude's context, title — tab
    /// separated. The
    /// title goes last: any program sets it, so a tab inside it stays
    /// inside it. The Mac writes the action without tabs.
    public static let listFormat = [
        "#{session_id}", "#{session_name}", "#{@lostty_surface}", "#{@lostty_owner}",
        "#{\(labelOption)}", "#{\(claudeOption)}", "#{session_activity}",
        "#{pane_current_command}", "#{pane_current_path}", "#{\(skinOption)}", "#{\(actionOption)}",
        "#{\(contextOption)}", "#{pane_title}",
    ].joined(separator: "\t")

    /// The wait-for channel tmux hooks, the Mac and the phone signal when
    /// sessions change.
    public static let changedChannel = "lostty-changed"

    /// Who ended a session, kept in `@lostty_end_<n>` after it is gone.
    public enum EndTag {
        public static let macClose = "mac-close"
        public static let macQuit = "mac-quit"
        public static let phonePrefix = "phone:"

        public static func phone(_ device: String) -> String { phonePrefix + device }
    }

    /// The global option that keeps why session `sessionID` ended
    /// ("$3" → "@lostty_end_3"). Ids restart only with the server, which
    /// drops the options too.
    public static func endOption(sessionID: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return "@lostty_end_\(sessionID.dropFirst())"
    }

    static var tmux: String { "\(pathPrefix) tmux -u -L lostty" }

    /// Prints a line each time sessions change, until the Mac has no tmux
    /// server (wait-for exits 1). `-f /dev/null`: never starts a server.
    public static var watchCommand: String {
        "while \(tmux) -f /dev/null wait-for \(changedChannel); do echo; done"
    }

    /// SSH commands have no locale, and without UTF-8 tmux turns the tab
    /// separators into `_`, so `-u` keeps them. Runs `listScript` in
    /// /bin/sh whatever the login shell is.
    public static var listCommand: String {
        "/bin/sh -c \(shellQuote(listScript))"
    }

    /// The sessions (`listFormat`), each line led by the repo folder and
    /// branch of its pane's folder and whether its Mac Lostty still runs
    /// (see `parseListing`). Reads `.git` and `HEAD` itself rather than
    /// running git: no process per session, and no Command Line Tools
    /// prompt on a Mac without git. A `.git` in the home folder doesn't
    /// count (a dotfiles repo), as for skins. A Lostty runs while its pid
    /// does (`kill -0`, the Mac's own rule; the phone logs in as the Mac's
    /// user). For a session whose Claude works, the last line of its pane
    /// that looks like Claude's working line ("✳ Incubating… (3m 51s)").
    /// Exits as tmux did, so "no server" (1) and "no tmux" (127) still
    /// read.
    public static var listScript: String {
        listScript(
            listing: "\(tmux) list-sessions -F "
                + shellQuote("#{pane_current_path}\t#{@lostty_owner}\t" + listFormat),
            capture: "\(tmux) capture-pane -pJ -t")
    }

    /// `listing` prints the sessions, each line led by its folder and its
    /// Mac Lostty's pid. `capture` followed by a session id prints its
    /// pane. The working line is matched by bytes (SSH commands have no
    /// locale): one of Claude's glyphs, a space, then an ellipsis.
    static func listScript(listing: String, capture: String) -> String {
        """
        t=$(printf '\\t'); o=$(\(listing)) || exit $?
        printf '%s\\n' "$o" | while IFS= read -r l; do
        d=${l%%"$t"*}; l=${l#*"$t"}; p=${l%%"$t"*}; l=${l#*"$t"}; g= h= r= b= a= s=
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then a=1; fi
        c=$l; n=0; while [ $n -lt 5 ]; do c=${c#*"$t"}; n=$((n+1)); done
        case ${c%%"$t"*} in working|agents)
        s=$({ \(capture) "${l%%"$t"*}"; } </dev/null 2>/dev/null | grep -E '^ *(·|✢|✳|✶|✻|✽) .*…' | tail -n 1 | tr '\\t' ' ');;
        esac
        while [ -n "$d" ] && [ "$d" != "$HOME" ]; do
        if [ -d "$d/.git" ]; then g=$d/.git; break; fi
        if [ -f "$d/.git" ]; then IFS= read -r g < "$d/.git"; g=${g#gitdir: }; case $g in /*) ;; *) g=$d/$g;; esac; break; fi
        d=${d%/*}
        done
        if [ -n "$g" ]; then
        case $g in */.git/worktrees/*) r=${g%%/.git/worktrees/*}; r=${r##*/};; *) r=${d##*/};; esac
        IFS= read -r h 2>/dev/null < "$g/HEAD"
        case $h in "ref: refs/heads/"*) b=${h#ref: refs/heads/};; esac
        fi
        printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$r" "$b" "$a" "$s" "$l"
        done
        """
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
            + "exec env LANG=\"${LANG:-en_US.UTF-8}\" \(tmux) -f /dev/null attach-session -t \(shellQuote(sessionID))"
    }

    /// Ends session `sessionID` (and with it the Mac window showing it),
    /// first noting that this phone (`device`) closed it. Exits 1 (without
    /// killing) if the id now names a different session.
    public static func killCommand(sessionID: String, name: String, device: String) throws -> String {
        let option = try endOption(sessionID: sessionID)
        return nameGuard(sessionID: sessionID, name: name)
            + "\(tmux) set-option -g \(option) \(shellQuote(EndTag.phone(device))) \\; kill-session -t \(shellQuote(sessionID))"
    }

    /// Names session `sessionID` (nil: back to the automatic name), then
    /// wakes every watcher. The label is cleaned here too (a trailing ";"
    /// would read as a tmux command separator). Exits 1 if the id now names
    /// a different session.
    public static func renameCommand(sessionID: String, name: String, label: String?) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        let set = label.flatMap(SessionLabel.cleanLabel).map {
            "set-option -t \(shellQuote(sessionID)) \(labelOption) \(shellQuote($0))"
        } ?? "set-option -u -t \(shellQuote(sessionID)) \(labelOption)"
        return nameGuard(sessionID: sessionID, name: name) + "\(tmux) \(set) \\; wait-for -S \(changedChannel)"
    }

    /// The largest texture tile read (a 220-pixel PNG is far smaller).
    public static let tileLimit = 1 << 20

    /// Prints the texture tile at `path` (on the Mac) as base64, refusing
    /// anything over `tileLimit`; nil for a path that isn't a PNG's.
    public static func readTileCommand(path: String) -> String? {
        guard path.hasPrefix("/"), path.hasSuffix(".png"), !path.contains("/../"),
              !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        let file = shellQuote(path)
        return "[ $(wc -c < \(file)) -le \(tileLimit) ] && base64 < \(file)"
    }

    /// Line 1: `present` or `gone`; line 2: the end tag, if any.
    public static func endProbeCommand(sessionID: String) throws -> String {
        let option = try endOption(sessionID: sessionID)
        return "T=$(\(tmux) -f /dev/null show-options -gqv \(shellQuote(option)) 2>/dev/null); "
            + "if \(tmux) -f /dev/null has-session -t \(shellQuote(sessionID)) 2>/dev/null; then echo present; else echo gone; fi; "
            + "printf '%s\\n' \"$T\""
    }

    public static func parseEndProbe(_ output: String) -> EndProbe? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first == "present" || first == "gone" else { return nil }
        let tag = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
        return EndProbe(exists: first == "present", tag: tag.isEmpty ? nil : tag)
    }

    /// `-f /dev/null`: display-message must not start a server either.
    private static func nameGuard(sessionID: String, name: String) -> String {
        "[ \"$(\(tmux) -f /dev/null display-message -p -t \(shellQuote(sessionID)) "
            + "'#{session_name}' 2>/dev/null)\" = \(shellQuote(name)) ] || exit 1; "
    }

    /// `tmux list-sessions -F listFormat` output.
    public static func parse(_ output: String) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { parseLine($0) }
    }

    /// `listScript` output: each line is repo, branch, whether the owner
    /// runs ("1" or empty), Claude's working line, then a `parse` line. A
    /// session whose Lostty is gone (crashed, before the Mac reopens it)
    /// has no owner: no window shows it, and its Claude state is stale.
    /// `now`: when it was listed, which the working line's time runs on from.
    public static func parseListing(_ output: String, now: Date = Date()) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard f.count == 5, var session = parseLine(f[4]) else { return nil }
            session.repo = f[0].isEmpty ? nil : String(f[0])
            session.branch = f[1].isEmpty ? nil : String(f[1])
            if f[2].isEmpty { session.owner = nil }
            session.spinner = ClaudeSpinner(line: String(f[3]), seenAt: now)
            return session
        }
    }

    private static func parseLine(_ line: Substring) -> RemoteSession? {
        let f = line.split(separator: "\t", maxSplits: 12, omittingEmptySubsequences: false).map(String.init)
        guard f.count == 13, isSessionID(f[0]) else { return nil }
        return RemoteSession(
            id: f[0],
            name: f[1],
            surface: f[2].isEmpty ? nil : f[2],
            owner: Int32(f[3]),
            label: f[4].isEmpty ? nil : f[4],
            claude: ClaudeActivity(rawValue: f[5]),
            action: f[10].isEmpty ? nil : f[10],
            title: f[12],
            path: f[8],
            command: f[7],
            activity: TimeInterval(f[6]).map { Date(timeIntervalSince1970: $0) },
            skin: SessionSkin(encoded: f[9]),
            context: SessionContext(encoded: f[11]))
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

/// The phone re-lists at most this often while changes stream in.
public enum ListPacing {
    public static let interval: TimeInterval = 0.3
    /// And this often while a Claude works: its working line (the word,
    /// the tokens) moves on without tmux saying anything changed.
    public static let whileWorking: TimeInterval = 4

    public static func delay(sinceLastList last: Date, now: Date) -> TimeInterval {
        max(0, interval - now.timeIntervalSince(last))
    }
}

extension RemoteSession {
    /// `session` as `listed` has it now, found by id: the Mac renames a
    /// session when its shell changes project. Only for a session the
    /// caller is attached to, which proves the id still names it (ids
    /// restart with the tmux server).
    public static func current(of session: RemoteSession, in listed: [RemoteSession]) -> RemoteSession? {
        listed.first { $0.id == session.id }
    }
}

/// Why Rename didn't take: the Mac's tmux refused it because the session
/// is gone, or because its name no longer matches (the Mac renamed it).
public enum RenameFailure: Equatable, Sendable {
    case ended
    case changed

    /// Decided from a list taken after the refusal.
    public static func after(sessionID: String, listed: [RemoteSession]) -> RenameFailure {
        listed.contains { $0.id == sessionID } ? .changed : .ended
    }

    public var message: String {
        switch self {
        case .ended: "Couldn't rename: that session has ended."
        case .changed: "Couldn't rename: the session changed on your Mac. Try again."
        }
    }
}
