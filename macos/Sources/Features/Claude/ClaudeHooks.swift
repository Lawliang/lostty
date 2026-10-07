#if os(macOS)
import Foundation

/// `+claude-hooks status` output.
enum ClaudeHooksStatus: String {
    case installed, partial, notInstalled = "not-installed", unreadable

    init?(cliOutput: String) {
        self.init(rawValue: cliOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Runs the bundled binary's `+claude-hooks` (the editing logic lives in
/// Zig: src/cli/claude_hooks.zig).
struct ClaudeHooksCLI {
    struct Result {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    var binary: URL? = Bundle.main.executableURL

    func run(_ op: String, agent: HookAgent? = nil) -> Result {
        guard let binary else { return Result(exitCode: -1, stdout: "", stderr: "Lostty binary not found") }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["+claude-hooks", op] + (agent.map { ["--agent=\($0.rawValue)"] } ?? [])
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    func status(agent: HookAgent? = nil) -> ClaudeHooksStatus? {
        let result = run("status", agent: agent)
        guard result.exitCode == 0 else { return nil }
        return ClaudeHooksStatus(cliOutput: result.stdout)
    }
}

enum ClaudeHooksPrompt {
    /// Shown after a successful install or remove. Claude Code reads hooks
    /// when a session starts, so running sessions need a restart.
    static func successMessage(for op: String) -> String? {
        switch op {
        case "install": "Hooks installed. Restart any running Claude or Codex sessions to see the trace. "
            + "Codex asks you to approve Lostty's hooks the first time."
        case "remove": "Hooks removed. Restart any running Claude or Codex sessions to finish turning the trace off."
        default: nil
        }
    }
}
#endif
