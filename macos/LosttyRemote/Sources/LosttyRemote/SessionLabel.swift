import Foundation

/// What a session's row says, on the phone and in the Mac's menu bar.
public struct SessionRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case shell
        case claude
    }

    public enum Status: Equatable, Sendable {
        case waiting
        case working
        /// "now", "5m ago", …; empty when tmux didn't say.
        case lastUsed(String)
    }

    public var id: String
    /// A name you typed, else the Claude task, else the project.
    public var title: String
    public var project: String
    public var kind: Kind
    public var openOnMac: Bool
    public var status: Status

    /// "lostty · claude · Open on Mac"
    public var detail: String {
        ([project, kind.rawValue] + (openOnMac ? ["Open on Mac"] : [])).joined(separator: " · ")
    }

    /// "Waiting", "Working", or when it was last used.
    public var statusText: String {
        switch status {
        case .waiting: "Waiting"
        case .working: "Working"
        case .lastUsed(let text): text
        }
    }
}

/// Sessions in list order: those open on the Mac, then the rest.
public struct SessionGroups: Equatable, Sendable {
    public var open: [RemoteSession]
    public var notOpen: [RemoteSession]
}

/// Turns tmux's view of a session into what a person reads. One
/// implementation for the phone's list and the Mac's menu bar.
public enum SessionLabel {
    public static func row(for session: RemoteSession, now: Date) -> SessionRow {
        let project = Self.project(path: session.path, name: session.name)
        let claude = Self.isClaude(session)
        let openOnMac = session.owner != nil
        let typed = session.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = claude ? Self.cleanTitle(session.title) : ""
        let title = !typed.isEmpty ? typed : (!task.isEmpty ? task : project)
        let status: SessionRow.Status
        switch openOnMac ? session.claude : nil {
        case .waiting?: status = .waiting
        case .working?: status = .working
        case nil: status = .lastUsed(Self.relative(session.activity, now: now))
        }
        return SessionRow(
            id: session.id, title: title, project: project, kind: claude ? .claude : .shell,
            openOnMac: openOnMac, status: status)
    }

    /// Waiting first, then most recently used; sessions no Mac window shows
    /// go in their own group after.
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
        return SessionGroups(open: sorted.filter { $0.owner != nil }, notOpen: sorted.filter { $0.owner == nil })
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
