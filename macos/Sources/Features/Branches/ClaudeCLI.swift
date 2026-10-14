#if os(macOS)
import Foundation

enum SummaryError: Error, Equatable, Sendable {
    case timedOut
    case cancelled
    case git
    case failed(String)

    var message: String {
        switch self {
        case .timedOut: "Claude took longer than a minute."
        case .cancelled: "Cancelled."
        case .git: "Couldn't read this branch's changes."
        case .failed(let message): message
        }
    }
}

/// What `claude -p --output-format json` prints: the answer, whether it is
/// an error, and the run's tokens per model.
struct ClaudeReply: Equatable, Sendable {
    var text: String
    var isError: Bool
    var usage: [String: TokenCounts]
}

/// The `claude` command line, run headless for branch summaries.
enum ClaudeCLI {
    static let timeout: TimeInterval = 60

    /// Headless, cheap model, no tools, nothing saved, no MCP servers, and no
    /// user/project settings (so the user's hooks and plugins don't run).
    /// JSON output, so each run reports its tokens for the usage breakdown.
    static let arguments = [
        "-p", "--model", "haiku", "--tools", "", "--no-session-persistence",
        "--strict-mcp-config", "--setting-sources", "", "--output-format", "json",
    ]

    /// `command -v claude` in a login shell; rc files may print other lines
    /// first, and an alias prints no path.
    static func parseLocate(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
    }

    /// Where `command` (`claude`, or the observer's `codex`) is, looked up
    /// through the user's login shell (Lostty started from the Dock has a
    /// bare PATH). Blocking, up to 5 s.
    static func locate(
        command: String = "claude",
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) -> String? {
        guard let result = ProcessRunner.run(shell, ["-lic", "command -v \(command)"], timeout: 5),
              result.status == 0,
              let path = parseLocate(result.stdout),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// `--output-format json`'s `{"type":"result",…}` object; nil for
    /// anything else (a stand-in that prints plain text, a crash).
    static func parseReply(_ stdout: String) -> ClaudeReply? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(stdout.utf8))) as? [String: Any],
              object["type"] as? String == "result" else { return nil }
        var usage: [String: TokenCounts] = [:]
        for (model, value) in object["modelUsage"] as? [String: Any] ?? [:] {
            guard let counts = value as? [String: Any] else { continue }
            func int(_ key: String) -> Int { (counts[key] as? NSNumber)?.intValue ?? 0 }
            usage[model] = TokenCounts(
                input: int("inputTokens"), output: int("outputTokens"),
                cacheWrite: int("cacheCreationInputTokens"), cacheRead: int("cacheReadInputTokens"))
        }
        return ClaudeReply(
            text: (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            isError: object["is_error"] as? Bool == true, usage: usage)
    }

    static func interpret(_ result: ProcessResult?, cancelled: Bool) -> Result<String, SummaryError> {
        if cancelled { return .failure(.cancelled) }
        guard let result else { return .failure(.timedOut) }
        if let reply = parseReply(result.stdout) {
            guard result.status == 0, !reply.isError else {
                return .failure(.failed(
                    firstLine(reply.text) ?? firstLine(result.stderr) ?? "Claude exited with status \(result.status)"))
            }
            return reply.text.isEmpty ? .failure(.failed("Claude returned nothing")) : .success(reply.text)
        }
        guard result.status == 0 else {
            return .failure(.failed(firstLine(result.stderr + "\n" + result.stdout)
                ?? "Claude exited with status \(result.status)"))
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.failed("Claude returned nothing")) }
        return .success(text)
    }

    /// The run's tokens per model, when it printed `--output-format json`
    /// and used any; an error that used tokens counts too.
    static func usage(_ result: ProcessResult?) -> [String: TokenCounts]? {
        guard let reply = result.flatMap({ parseReply($0.stdout) }), !reply.usage.isEmpty else { return nil }
        return reply.usage
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
#endif
