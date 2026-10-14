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

/// The `claude` command line, run headless for branch summaries.
enum ClaudeCLI {
    static let timeout: TimeInterval = 60

    /// Headless, cheap model, no tools, nothing saved, no MCP servers, and no
    /// user/project settings (so the user's hooks and plugins don't run).
    static let arguments = [
        "-p", "--model", "haiku", "--tools", "", "--no-session-persistence",
        "--strict-mcp-config", "--setting-sources", "",
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

    static func interpret(_ result: ProcessResult?, cancelled: Bool) -> Result<String, SummaryError> {
        if cancelled { return .failure(.cancelled) }
        guard let result else { return .failure(.timedOut) }
        guard result.status == 0 else {
            let line = (result.stderr + "\n" + result.stdout)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return .failure(.failed(line ?? "Claude exited with status \(result.status)"))
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.failed("Claude returned nothing")) }
        return .success(text)
    }
}
#endif
