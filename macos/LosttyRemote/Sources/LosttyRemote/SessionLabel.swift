import Foundation

/// What a session's row says, on the phone and in the Mac's menu bar.
public struct SessionRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case shell
        case claude
    }

    /// A session open on the Mac is waiting (Claude finished or asks, and
    /// you haven't looked), working, ready (seen, used in the last
    /// `SessionLabel.idleAfter`) or idle. One no Mac window shows only
    /// says when it was last used.
    public enum Status: Equatable, Sendable {
        case waiting
        case working
        case ready
        /// How long since it was used: "2h ago"; empty when tmux didn't say.
        case idle(String)
        /// No Mac window shows it: "now", "5m ago", …; empty when tmux
        /// didn't say.
        case lastUsed(String)
    }

    public var id: String
    /// A name you typed, else the Claude task, else the project.
    public var title: String
    public var project: String
    /// The branch checked out in the session's folder, if git says one.
    public var branch: String?
    public var kind: Kind
    /// A Mac window shows it.
    public var openOnMac: Bool
    public var status: Status
    /// The Mac pane's skin, for the phone's row.
    public var skin: SessionSkin?
    /// What its Claude is doing, over the state: "Editing Foo.swift"
    /// while working, "Allow? Run the tests" while it asks permission;
    /// nil otherwise.
    public var action: String?
    /// Claude's working line, while working and the pane showed one.
    public var spinner: ClaudeSpinner?

    /// "lostty/skins", or "lostty" without a branch.
    public var detail: String {
        branch.map { "\(project)/\($0)" } ?? project
    }

    /// "Waiting", "Working", "Ready", or when it was last used.
    public var statusText: String {
        switch status {
        case .waiting: "Waiting"
        case .working: "Working"
        case .ready: "Ready"
        case .idle(let text), .lastUsed(let text): text
        }
    }
}

/// Sessions in list order, under "Active Terminals" (a Mac window shows
/// them) and "Inactive Terminals" (none does).
public struct SessionGroups: Equatable, Sendable {
    public var active: [RemoteSession]
    public var inactive: [RemoteSession]
}

/// Turns tmux's view of a session into what a person reads. One
/// implementation for the phone's list and the Mac's menu bar.
public enum SessionLabel {
    /// Not typed into (or opened) for this long: idle, not ready. tmux's
    /// session_activity moves on input, not on output, so a log scrolling
    /// or Claude writing doesn't keep a terminal ready.
    public static let idleAfter: TimeInterval = 30 * 60

    public static func row(for session: RemoteSession, now: Date) -> SessionRow {
        // The repo's folder goes with a branch: a worktree's own name would
        // only repeat it. Without one, the worktree's name says the most.
        let fromName = Self.project(path: session.path, name: session.name)
        let project = session.branch == nil ? fromName : session.repo ?? fromName
        let claude = Self.isClaude(session)
        let openOnMac = session.owner != nil
        let typed = session.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = claude ? Self.cleanTitle(session.title) : ""
        let title = !typed.isEmpty ? typed : (!task.isEmpty ? task : project)
        let status: SessionRow.Status
        var action: String?
        var spinner: ClaudeSpinner?
        let used = Self.relative(session.activity, now: now)
        if !openOnMac {
            status = .lastUsed(used)
        } else if let claude = session.claude {
            status = claude == .waiting ? .waiting : .working
            // The Mac keeps an action through a wait only when Claude asks
            // permission for it.
            action = session.action.map { claude == .waiting ? "Allow? \($0)" : $0 }
            spinner = claude.isWorking ? session.spinner : nil
        } else if let activity = session.activity, now.timeIntervalSince(activity) < idleAfter {
            status = .ready
        } else {
            status = .idle(used)
        }
        return SessionRow(
            id: session.id, title: title, project: project, branch: session.branch, kind: claude ? .claude : .shell,
            openOnMac: openOnMac, status: status, skin: session.skin, action: action,
            spinner: spinner)
    }

    /// What closing `session` from the phone does, said before it happens:
    /// the terminal goes on the phone and the Mac alike.
    public static func closeWarning(for session: RemoteSession) -> (title: String, message: String) {
        let name = row(for: session, now: Date()).title
        let message = session.owner != nil
            ? "This closes the terminal on both your phone and your Mac, and stops whatever is running in it."
            : "This closes the terminal on your phone and ends it on your Mac, where it's running without a "
                + "window. Whatever is running in it stops."
        return ("Close \u{201C}\(name)\u{201D}?", message)
    }

    /// Waiting first, then most recently used; sessions no Mac window shows
    /// in their own group (never waiting: nothing keeps their Claude state).
    public static func ordered(_ sessions: [RemoteSession]) -> SessionGroups {
        func waiting(_ s: RemoteSession) -> Bool { s.owner != nil && s.claude == .waiting }
        func number(_ s: RemoteSession) -> Int { Int(s.id.dropFirst()) ?? 0 }
        let sorted = sessions.sorted { a, b in
            if waiting(a) != waiting(b) { return waiting(a) }
            let ta = a.activity ?? .distantPast
            let tb = b.activity ?? .distantPast
            if ta != tb { return ta > tb }
            return number(a) < number(b)
        }
        return SessionGroups(active: sorted.filter { $0.owner != nil }, inactive: sorted.filter { $0.owner == nil })
    }

    /// `.../<repo>/.claude/worktrees/<name>/...` reads `<repo>/<name>`;
    /// anything else is the session name without a trailing `-<digits>`.
    public static func project(path: String, name: String) -> String {
        if let marker = path.range(of: "/.claude/worktrees/") {
            let repo = (String(path[..<marker.lowerBound]) as NSString).lastPathComponent
            let worktree = path[marker.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            if !repo.isEmpty, !worktree.isEmpty { return "\(repo)/\(worktree)" }
        }
        guard let dash = name.lastIndex(of: "-"), dash > name.startIndex else { return name }
        let digits = name[name.index(after: dash)...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
        return String(name[..<dash])
    }

    /// The Mac says so, or the command is Claude Code's version number.
    public static func isClaude(_ session: RemoteSession) -> Bool {
        session.claude != nil || looksLikeVersion(session.command)
    }

    static func looksLikeVersion(_ command: String) -> Bool {
        guard let first = command.first, first.isASCII, first.isNumber, command.contains(".") else { return false }
        return command.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
    }

    public static func hasClaudeGlyph(_ title: String) -> Bool {
        title.unicodeScalars.first.map(isGlyph) ?? false
    }

    /// The title without a leading spinner or "✳" (and what follows it up
    /// to the text).
    public static func cleanTitle(_ title: String) -> String {
        var scalars = Substring(title).unicodeScalars
        if let first = scalars.first, isGlyph(first) {
            scalars = scalars.dropFirst()
            while scalars.first == "\u{FE0F}" { scalars = scalars.dropFirst() }
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    /// Claude Code's spinner frames and idle "✳", and Codex's braille dots.
    static func isGlyph(_ scalar: Unicode.Scalar) -> Bool {
        "◐◑◒◓✳✶✻✽✢".unicodeScalars.contains(scalar) || (0x2800...0x28FF).contains(scalar.value)
    }

    /// "now", "5m ago", "2h ago", "3d ago"; empty when unknown.
    public static func relative(_ activity: Date?, now: Date) -> String {
        guard let activity else { return "" }
        let seconds = max(0, now.timeIntervalSince(activity))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86400))d ago"
        }
    }

    /// A typed name as stored: control characters (tabs, newlines) become
    /// spaces, at most 80 characters, no trailing ";" (tmux would read one
    /// as a command separator). nil when nothing is left: that clears it.
    public static func cleanLabel(_ typed: String) -> String? {
        let scalars = typed.unicodeScalars.map { (s: Unicode.Scalar) -> Unicode.Scalar in
            s.properties.generalCategory == .control ? " " : s
        }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        if text.count > 80 { text = String(text.prefix(80)) }
        while text.hasSuffix(";") || text.hasSuffix(" ") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}
