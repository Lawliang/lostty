#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SummarizerTests {
    @Test func onlyAClaudeSubscriptionCounts() {
        #expect(Summarizer.claudeSignedIn(#"{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}"#))
        #expect(!Summarizer.claudeSignedIn(#"{"loggedIn": true, "authMethod": "api_key"}"#))
        #expect(!Summarizer.claudeSignedIn(#"{"loggedIn": false, "authMethod": "claude.ai"}"#))
        #expect(!Summarizer.claudeSignedIn("Not logged in"))
        #expect(Summarizer.claudeSignedIn("note: update available\n{\"loggedIn\": true, \"authMethod\": \"claude.ai\"}\n"))
    }

    @Test func onlyAChatGPTSignInCounts() {
        #expect(Summarizer.codexSignedIn("Logged in using ChatGPT\n"))
        #expect(!Summarizer.codexSignedIn("Logged in using an API key - sk-…\n"))
        #expect(!Summarizer.codexSignedIn("Not logged in\n"))
    }

    @Test func claudeComesFirstThenCodexThenApple() {
        let both: (String) -> String? = { "/bin/\($0)" }
        let signedIn: (String, [String]) -> String? = { path, _ in
            path.hasSuffix("claude") ? #"{"loggedIn":true,"authMethod":"claude.ai"}"# : "Logged in using ChatGPT"
        }
        #expect(Summarizer.detect(locate: both, status: signedIn, apple: { true }) == .claude("/bin/claude"))
        let codexOnly: (String, [String]) -> String? = { path, _ in
            path.hasSuffix("claude") ? #"{"loggedIn":true,"authMethod":"api_key"}"# : "Logged in using ChatGPT"
        }
        #expect(Summarizer.detect(locate: both, status: codexOnly, apple: { true }) == .codex("/bin/codex"))
        let nobody: (String, [String]) -> String? = { _, _ in "Not logged in" }
        #expect(Summarizer.detect(locate: both, status: nobody, apple: { true }) == .apple)
        #expect(Summarizer.detect(locate: { _ in nil }, status: signedIn, apple: { false }) == SummarizerKind.none)
    }

    @Test func theEnvironmentLeavesOutKeysAndPaneVariables() {
        let base = ["HOME": "/Users/me", "USER": "me", "TMPDIR": "/tmp/x", "LANG": "en_US.UTF-8",
                    "ANTHROPIC_API_KEY": "sk-ant", "OPENAI_API_KEY": "sk-oai", "CODEX_API_KEY": "k",
                    "LOSTTY_SURFACE": "abc", "LOSTTY_BIN": "/x", "TMUX": "/tmp/tmux", "PATH": "/evil",
                    "CODEX_HOME": "/Users/me/.codex"]
        let env = Summarizer.environment(for: "/Users/me/.nvm/bin/codex", base: base)
        #expect(env["HOME"] == "/Users/me" && env["USER"] == "me" && env["TMPDIR"] == "/tmp/x")
        #expect(env["CODEX_HOME"] == "/Users/me/.codex")
        #expect(env["PATH"] == "/Users/me/.nvm/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        for key in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CODEX_API_KEY", "LOSTTY_SURFACE", "LOSTTY_BIN", "TMUX"] {
            #expect(env[key] == nil)
        }
    }

    @Test func codexRunsLeanAndReadOnly() {
        let args = Summarizer.codexArguments(output: "/tmp/out.txt")
        #expect(args.first == "exec")
        #expect(args.contains("--ignore-user-config") && args.contains("--ephemeral") && args.contains("--skip-git-repo-check"))
        #expect(args.firstIndex(of: "-s").map { args[$0 + 1] } == "read-only")
        #expect(args.firstIndex(of: "-o").map { args[$0 + 1] } == "/tmp/out.txt")
        #expect(!args.contains("-m"))
        #expect(args.last == "-")
    }

    func script(_ name: String, _ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("summ-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func claudesAnswerIsWhatItPrints() async throws {
        let claude = try script("claude", "cat > /dev/null\necho '{\"built\":[],\"just_now\":\"hi\"}'")
        let result = await Summarizer.run(.claude(claude), prompt: "x", handle: RunHandle())
        #expect(result == .success(#"{"built":[],"just_now":"hi"}"#))
    }

    @Test func codexsAnswerIsItsOutputFile() async throws {
        let codex = try script("codex", """
        out=""
        while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
        cat > /dev/null
        echo "progress noise"
        echo '{"built":["a"],"just_now":"b"}' > "$out"
        """)
        let result = await Summarizer.run(.codex(codex), prompt: "x", handle: RunHandle())
        #expect(result == .success(#"{"built":["a"],"just_now":"b"}"#))
    }

    @Test func aFailingRunSaysWhy() async throws {
        let codex = try script("codex", "cat > /dev/null\necho 'Not logged in' >&2\nexit 1")
        #expect(await Summarizer.run(.codex(codex), prompt: "x", handle: RunHandle()) == .failure(.failed("Not logged in")))
        #expect(await Summarizer.run(.none, prompt: "x", handle: RunHandle()) == .failure(.failed(Summarizer.noSummarizer)))
    }

    @Test func eachKindHasItsWordLimit() {
        #expect(SummarizerKind.claude("/c").words == ObserverPrompt.cliWords)
        #expect(SummarizerKind.codex("/c").words == ObserverPrompt.cliWords)
        #expect(SummarizerKind.apple.words == ObserverPrompt.appleWords)
    }

    func tempLedger() -> UsageLedger {
        UsageLedger(url: FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json"))
    }

    @Test func claudeRunsRecordTheirTokens() async throws {
        let claude = try script("claude", #"""
        cat > /dev/null
        echo '{"type":"result","is_error":false,"result":"{\"built\":[],\"just_now\":\"hi\"}","modelUsage":{"claude-haiku-5-5":{"inputTokens":7,"outputTokens":3}}}'
        """#)
        let ledger = tempLedger()
        let result = await Summarizer.run(.claude(claude), prompt: "x", handle: RunHandle(), ledger: ledger)
        #expect(result == .success(#"{"built":[],"just_now":"hi"}"#))
        #expect(ledger.runs().map(\.source) == [.observer])
        #expect(ledger.runs().first?.tokens == ["claude-haiku-5-5": TokenCounts(input: 7, output: 3)])
    }

    @Test func codexRunsRecordNothing() async throws {
        let codex = try script("codex", """
        out=""
        while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
        cat > /dev/null
        echo '{"type":"result","is_error":false,"result":"x","modelUsage":{"m":{"inputTokens":1}}}'
        echo '{"built":["a"],"just_now":"b"}' > "$out"
        """)
        let ledger = tempLedger()
        _ = await Summarizer.run(.codex(codex), prompt: "x", handle: RunHandle(), ledger: ledger)
        #expect(ledger.runs().isEmpty)
    }

    @Test func theEnvironmentKeepsProxiesAndCertificates() {
        let base = ["HOME": "/Users/me", "HTTPS_PROXY": "http://proxy:8080", "https_proxy": "http://proxy:8080",
                    "HTTP_PROXY": "http://proxy:8080", "NO_PROXY": "localhost", "ALL_PROXY": "socks5://p",
                    "NODE_EXTRA_CA_CERTS": "/etc/corp.pem", "SSL_CERT_FILE": "/etc/ca.pem", "SSL_CERT_DIR": "/etc/certs"]
        let env = Summarizer.environment(for: "/bin/claude", base: base)
        for key in base.keys { #expect(env[key] == base[key]) }
    }
}
#endif
