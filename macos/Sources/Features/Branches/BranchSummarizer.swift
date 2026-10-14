#if os(macOS)
import Foundation

/// Lets Cancel kill a summary run from another thread.
final class RunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32?
    private var cancelled = false

    func started(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        self.pid = pid
        if cancelled { kill(pid, SIGKILL) }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let pid { kill(pid, SIGKILL) }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum BranchSummarizer {
    /// Reads `branch`'s commits and diff against `base` and asks `claude`
    /// for a summary. Blocking: call it off the main thread.
    static func run(
        branch: String, base: String, root: String, claude: String, handle: RunHandle,
        ledger: UsageLedger = .shared
    ) -> Result<String, SummaryError> {
        let commits = "refs/heads/\(base)..refs/heads/\(branch)"
        let changes = "refs/heads/\(base)...refs/heads/\(branch)"
        // Plain text whatever the user's config: no external diff tool
        // (difftastic) and no color codes in what Claude reads.
        guard let log = Git.run(["log", "--no-color", "--format=%s%n%b", commits], in: root),
              let diff = Git.run(["diff", "--no-ext-diff", "--no-color", changes], in: root, timeout: 15),
              let stat = Git.run(["diff", "--no-ext-diff", "--no-color", "--stat", changes], in: root)
        else { return .failure(.git) }
        guard !handle.isCancelled else { return .failure(.cancelled) }

        let prompt = SummaryPrompt.build(branch: branch, base: base, log: log, diff: diff, stat: stat)
        // Only what finding the login takes, with claude's own folder (node)
        // first on PATH: never an API key or pane variable from Lostty's own.
        let result = ProcessRunner.run(
            claude, ClaudeCLI.arguments,
            cwd: NSTemporaryDirectory(),
            environment: Summarizer.environment(for: claude), inheritEnvironment: false,
            stdin: prompt, timeout: ClaudeCLI.timeout, onStart: handle.started)
        if let tokens = ClaudeCLI.usage(result) { ledger.record(tokens, source: .branchSummary) }
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
    }
}
#endif
