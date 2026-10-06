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

    func run(_ op: String) -> Result {
        guard let binary else { return Result(exitCode: -1, stdout: "", stderr: "Lostty binary not found") }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["+claude-hooks", op]
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

    func status() -> ClaudeHooksStatus? {
        let result = run("status")
        guard result.exitCode == 0 else { return nil }
        return ClaudeHooksStatus(cliOutput: result.stdout)
    }
}

enum ClaudeHooksPrompt {
    /// Bump when the hook command format changes, to offer an update once.
    static let hookVersion = 1
    static let defaultsKey = "LosttyClaudeHooksPromptedVersion"

    /// Ask once per hook version, only people who use Claude (~/.claude
    /// exists) and only when install would help. An unreadable settings
    /// file is reported from the menu, never at launch.
    static func shouldPrompt(claudeDirExists: Bool, status: ClaudeHooksStatus?, promptedVersion: Int) -> Bool {
        guard claudeDirExists, promptedVersion < hookVersion else { return false }
        return status == .notInstalled || status == .partial
    }
}
#endif
