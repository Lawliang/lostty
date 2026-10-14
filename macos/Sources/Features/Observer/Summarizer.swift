#if os(macOS)
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who writes the observer's notes (spec §5), with the path of its CLI.
enum SummarizerKind: Equatable, Sendable {
    /// Claude Haiku on the Claude subscription.
    case claude(String)
    /// Codex on its default model, signed in with ChatGPT.
    case codex(String)
    /// Apple's on-device model.
    case apple
    case none

    /// The most words its prompt carries.
    var words: Int {
        self == .apple ? ObserverPrompt.appleWords : ObserverPrompt.cliWords
    }
}

/// Finds a summarizer the user is signed in to, never an API key, and runs it.
enum Summarizer {
    static let noSummarizer = "Sign in to Claude Code or Codex, or turn on Apple Intelligence, to get summaries."

    /// `claude auth status` (JSON) says the Claude subscription login.
    static func claudeSignedIn(_ status: String) -> Bool {
        guard let open = status.firstIndex(of: "{"), let close = status.lastIndex(of: "}"), open < close,
              let object = (try? JSONSerialization.jsonObject(with: Data(status[open...close].utf8))) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true && object["authMethod"] as? String == "claude.ai"
    }

    /// `codex login status` says a ChatGPT sign-in (not an API key).
    static func codexSignedIn(_ status: String) -> Bool {
        status.contains("Logged in using ChatGPT")
    }

    /// What a run gets for its environment: none of Lostty's own (no API
    /// keys, no pane variables for the agent's hooks to report with), just
    /// what finding its login takes, and PATH with the CLI's own folder
    /// first (node, for a script).
    static func environment(
        for executable: String,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        // Proxies and certificates too: behind a company proxy the CLIs can't
        // reach their servers without them, and they pick no billing.
        let kept = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "CLAUDE_CONFIG_DIR", "CODEX_HOME",
                    "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "NO_PROXY", "no_proxy",
                    "ALL_PROXY", "all_proxy", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE", "SSL_CERT_DIR"]
        var env = base.filter { kept.contains($0.key) }
        let folder = (executable as NSString).deletingLastPathComponent
        env["PATH"] = "\(folder):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }

    /// No user config (plugins, MCP servers), nothing saved, read-only,
    /// low reasoning, the prompt on stdin, the answer in `output`.
    static func codexArguments(output: String) -> [String] {
        ["exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
         "-c", "model_reasoning_effort=low", "-o", output, "-"]
    }

    /// The first summarizer the user is signed in to. Blocking (login
    /// shells, `auth status`): call it off the main thread.
    static func detect(
        locate: (String) -> String? = { ClaudeCLI.locate(command: $0) },
        status: (String, [String]) -> String? = { Summarizer.statusOutput($0, $1) },
        apple: () -> Bool = { Summarizer.appleAvailable }
    ) -> SummarizerKind {
        if let path = locate("claude"), let out = status(path, ["auth", "status"]), claudeSignedIn(out) {
            return .claude(path)
        }
        if let path = locate("codex"), let out = status(path, ["login", "status"]), codexSignedIn(out) {
            return .codex(path)
        }
        return apple() ? .apple : .none
    }

    static func statusOutput(_ path: String, _ args: [String]) -> String? {
        guard let result = ProcessRunner.run(
            path, args, cwd: NSTemporaryDirectory(), environment: environment(for: path),
            inheritEnvironment: false, timeout: 15) else { return nil }
        return result.stdout + "\n" + result.stderr
    }

    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// The model's answer to `prompt`. `handle` cancels a CLI run; cancel
    /// the calling task for Apple's.
    static func run(
        _ kind: SummarizerKind, prompt: String, handle: RunHandle, ledger: UsageLedger = .shared
    ) async -> Result<String, SummaryError> {
        switch kind {
        case .claude(let path):
            return await Task.detached(priority: .utility) {
                Summarizer.runClaude(path, prompt: prompt, handle: handle, ledger: ledger)
            }.value
        case .codex(let path):
            return await Task.detached(priority: .utility) { Summarizer.runCodex(path, prompt: prompt, handle: handle) }.value
        case .apple:
            return await runApple(prompt)
        case .none:
            return .failure(.failed(noSummarizer))
        }
    }

    private static func runClaude(
        _ path: String, prompt: String, handle: RunHandle, ledger: UsageLedger
    ) -> Result<String, SummaryError> {
        let result = ProcessRunner.run(
            path, ClaudeCLI.arguments, cwd: NSTemporaryDirectory(), environment: environment(for: path),
            inheritEnvironment: false, stdin: prompt, timeout: ClaudeCLI.timeout, onStart: handle.started)
        if let tokens = ClaudeCLI.usage(result) { ledger.record(tokens, source: .observer) }
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
    }

    private static func runCodex(_ path: String, prompt: String, handle: RunHandle) -> Result<String, SummaryError> {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("lostty-observer-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let result = ProcessRunner.run(
            path, codexArguments(output: output.path), cwd: NSTemporaryDirectory(),
            environment: environment(for: path), inheritEnvironment: false, stdin: prompt,
            timeout: ClaudeCLI.timeout, onStart: handle.started)
        // Codex prints its progress; the answer is in the output file.
        switch ClaudeCLI.interpret(result.map { ProcessResult(status: $0.status, stdout: "-", stderr: $0.stderr) },
                                   cancelled: handle.isCancelled) {
        case .failure(let error):
            return .failure(error)
        case .success:
            let text = ((try? String(contentsOf: output, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .failure(.failed("Codex returned nothing")) : .success(text)
        }
    }

    private static func runApple(_ prompt: String) async -> Result<String, SummaryError> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession().respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? .failure(.failed("Apple Intelligence returned nothing")) : .success(text)
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch {
                return .failure(.failed("Apple Intelligence couldn't summarize this (\(error.localizedDescription))."))
            }
        }
        #endif
        return .failure(.failed(noSummarizer))
    }
}
#endif
