#if os(macOS)
import Foundation

/// Which agent wrote a conversation file.
enum TranscriptAgent: Equatable, Sendable {
    case claude, codex
}

/// A conversation file the turn observer may read (spec §2). Anything in a
/// pane can print a LOSTTY_CLAUDE user var, so a path from a hook is only a
/// hint: it must resolve, through any symlinks and `..`, to an existing
/// `.jsonl` file under Claude's or Codex's own folders.
struct TranscriptLocation: Equatable, Sendable {
    var url: URL
    var agent: TranscriptAgent

    static func allowed(
        _ path: String,
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TranscriptLocation? {
        guard path.hasPrefix("/"), let resolved = realPath(path), resolved.hasSuffix(".jsonl") else { return nil }
        for (root, agent) in roots(home: home, environment: environment) {
            guard let base = realPath(root) else { continue }
            if resolved.hasPrefix(base + "/") {
                return TranscriptLocation(url: URL(fileURLWithPath: resolved), agent: agent)
            }
        }
        return nil
    }

    /// Claude's projects and Codex's sessions, in their default homes and
    /// wherever Lostty's own environment moves them.
    static func roots(home: String, environment: [String: String]) -> [(String, TranscriptAgent)] {
        var roots: [(String, TranscriptAgent)] = [(home + "/.claude/projects", .claude), (home + "/.codex/sessions", .codex)]
        if let dir = environment["CLAUDE_CONFIG_DIR"], dir.hasPrefix("/") { roots.append((dir + "/projects", .claude)) }
        if let dir = environment["CODEX_HOME"], dir.hasPrefix("/") { roots.append((dir + "/sessions", .codex)) }
        return roots
    }

    /// The path with every symlink and `..` resolved; nil when it doesn't exist.
    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
#endif
