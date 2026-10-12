#if os(macOS)
import Foundation

/// Runs `/usr/bin/git -C <dir> …` for the Branches panel. Blocking: call it
/// off the main thread.
enum Git {
    static let executable = "/usr/bin/git"

    /// stdout when git exits 0; nil when it fails or takes longer than
    /// `timeout`. Reads never take `index.lock` (GIT_OPTIONAL_LOCKS=0), so
    /// they can't get in the way of git commands run in a pane.
    static func run(_ args: [String], in dir: String, timeout: TimeInterval = 5) -> String? {
        guard let result = ProcessRunner.run(
            executable, ["-C", dir] + args,
            environment: ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"],
            timeout: timeout),
            result.status == 0 else { return nil }
        return result.stdout
    }
}
#endif
