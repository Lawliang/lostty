# Lostty Usage Breakdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking the usage bar shows, under Current session and Weekly · all models, roughly how many of the limit's percentage points went to Claude Code in Lostty panes and how many to Lostty's own Claude runs.

**Architecture:** Lostty's own Claude runs switch to `--output-format json`, so `ClaudeCLI` can read each run's tokens; the observer's and branch summarizer's runs record them in an on-disk `UsageLedger`, which also keeps the Claude conversation files Lostty panes report at each turn's end. When the popover opens, a `UsageCounter` actor reads those files (and their subagents' files) off the main thread, counting each reply once, and `UsageBreakdown` splits each limit's percentage by weighted tokens (`UsageWeights`).

**Tech Stack:** Swift / SwiftUI (macOS), Swift Testing, Foundation (`FileHandle`, `JSONSerialization`, `Date.ISO8601FormatStyle`), the `claude` CLI's `-p --output-format json`.

**Spec:** `docs/superpowers/specs/2026-10-14-lostty-usage-breakdown-design.md`

**Runs after:** `docs/superpowers/plans/2026-10-14-lostty-mascot-observer.md` Tasks 1–7 (the hook's `"transcript"`, `ClaudeRuntime.turnEnded`, `TranscriptLocation`, `Summarizer`, and the AppDelegate wiring). Don't start until those are committed. Its Task 8 (the bubble) can land in any order with this plan.

## Global Constraints

- Mac-only code: every new Swift file is wrapped in `#if os(macOS)` … `#endif`. `macos/Sources` and `macos/Tests` are Xcode synchronized folders: new files join the targets by themselves, so never edit `project.pbxproj` to add a file.
- New sources go in `macos/Sources/Features/Usage/`; new tests in `macos/Tests/Usage/` (Swift Testing: `import Testing`, `@testable import Lostty`, `struct …Tests`, `@Test func …`), except additions to existing suites named in a task.
- Commands: one Mac suite `macos/skins-test.sh <SuiteName>` (prints `** TEST SUCCEEDED **`); Mac build `macos/build.nu`. `swiftlint` and `prettier` aren't installed: skip them.
- The two parts are exactly "Claude Code" (Lostty panes' Claude conversations, subagents included) and "Lostty" (the observer's and branch summaries' Claude runs). Codex, Apple's model, Claude Code outside Lostty and claude.ai are not parts.
- Weights (spec §1): input × 1, output × 5, cache writes × 1.25, cache reads × 0.1; Haiku × 1, Sonnet × 3, Opus × 5, Fable × 5, any other model × 5.
- Windows: Current session `[resetsAt − 5 hours, now]`, Weekly · all models `[resetsAt − 7 days, now]`. Weekly · Fable gets no breakdown.
- The ledger is `Lostty/usage-ledger.json` in Application Support (like `SummaryCache`'s `Lostty/branch-summaries.json`) and keeps 8 days. Counts are reused for 60 seconds.
- Copy, exactly: "Claude Code ≈ 41 · Lostty ≈ 1" (a part under half a point is "<1"), "Counting…", "Estimated from Claude use in Lostty."
- Commits: each task commits only its own files, staged by explicit path (`git add <paths>`), message prefixed `lostty: usage:` and ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `README.md`, `macos/ship-phone.sh`, or the user's uncommitted mascot files. Never push.
- Another Claude session may edit this working tree: re-read a file right before editing it, anchor edits on quoted text, never revert changes you didn't make.
- Never install a build on the Mac or phone, run `macos/install-skins.sh`, or quit Lostty unless the user asks (Quit ends every terminal session). When testing the real `claude` CLI, keep prompts to a word or two: the user pays for the tokens.

## Review Focus

1. **A week of very large conversation files** (hundreds of MB in all) must not stall the window or load whole files into memory: the counter is an actor (off the main thread) and reads in chunks, carrying a partial line across chunk boundaries. Pinned in Task 5 (`aSmallChunkSizeCountsTheSame`).
2. **A conversation file that got shorter** (replaced or rewritten) must be counted again from the start, never with a stale offset that skips or doubles replies. Pinned in Task 5 (`aFileThatShrankStartsOver`).
3. **Opening the popover before any limit report, or after a limit has reset**, must show no breakdown and no "0 · 0" line. Pinned in Task 6 (`noLimitOrAResetLimitHasNoBreakdown`).
4. **An observer run and a branch summary finishing at the same moment** on two background threads must both be recorded. Pinned in Task 3 (`recordsFromManyThreadsAtOnce`).
5. **Timestamps with and without fractional seconds** (`…T05:45:50.990Z` and `…T05:45:50Z`) must both count. Pinned in Task 5 (`timestampsWithOrWithoutFractionsCount`).

## Decisions This Plan Makes That the Spec Leaves Open

- `ClaudeCLI.interpret` keeps its signature and returns the JSON's `result` text; a separate `ClaudeCLI.usage(_:)` reads the tokens, so no caller of `interpret` changes. A JSON error (`"is_error": true`) shows its `result` text as the failure. Plain-text output (the test stand-ins, or anything that isn't a `{"type":"result",…}` object) works as today.
- A run that fails after using tokens still records them.
- Only Claude conversations go in the ledger; a Codex pane's file is ignored (it uses another plan).
- The ledger is rewritten on every turn end and run. It holds paths and token counts only, never conversation text.
- Files not modified since the week's start are skipped without reading.
- With no `resetsAt` in the report, the window ends now. While the limit shows 0%, there is no breakdown.
- A part under half a point reads "Lostty <1" (no ≈). The rounded parts add up to the percentage the row shows.
- Conversations from before this build were never reported, so for the first week the breakdown covers only conversations that ended a turn since.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `macos/Sources/Features/Usage/UsageWeights.swift` | `TokenCounts`; `UsageWeights`: weighted tokens by kind and model |
| Modify `macos/Sources/Features/Branches/ClaudeCLI.swift` | `--output-format json`; `ClaudeReply`, `parseReply`, `interpret` reads JSON, `usage(_:)` |
| Create `macos/Sources/Features/Usage/UsageLedger.swift` | `LosttyRunSource`, `LosttyRun`; `UsageLedger`: reported conversations and Lostty's runs, on disk, 8 days, thread-safe |
| Modify `macos/Sources/Features/Branches/BranchSummarizer.swift` | Records each run's tokens as `.branchSummary` |
| Modify `macos/Sources/Features/Observer/Summarizer.swift` | Records each Claude run's tokens as `.observer` |
| Modify `macos/Sources/App/macOS/AppDelegate.swift` | Each turn's end also reports the conversation to the ledger |
| Create `macos/Sources/Features/Usage/UsageCounter.swift` | `UsagePart`, `WeightedUse`; `UsageCounter` actor: replies in conversation and subagent files, counted once, read incrementally |
| Create `macos/Sources/Features/Usage/UsageBreakdown.swift` | Splitting a limit's percentage; the row's text |
| Create `macos/Sources/Features/Usage/UsageBreakdownRuntime.swift` | Counting when the popover opens, reuse for a minute, each row's line |
| Modify `macos/Sources/Features/Claude/ClaudeUsageBar.swift` | `ClaudeUsageDetails` shows the lines and the footnote |
| Tests: `macos/Tests/Usage/*.swift` (new); additions to `macos/Tests/Branches/ClaudeCLITests.swift`, `macos/Tests/Branches/BranchSummarizerTests.swift`, `macos/Tests/Observer/SummarizerTests.swift` | |

---

### Task 1: Tokens and their weights

**Files:**
- Create: `macos/Sources/Features/Usage/UsageWeights.swift`
- Test: `macos/Tests/Usage/UsageWeightsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct TokenCounts: Codable, Equatable, Sendable { var input = 0; var output = 0; var cacheWrite = 0; var cacheRead = 0 }`
  - `enum UsageWeights { static func model(_ id: String) -> Double; static func weight(_ tokens: TokenCounts, model id: String) -> Double }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Usage/UsageWeightsTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageWeightsTests {
    @Test func tokenKindsWeighDifferently() {
        let tokens = TokenCounts(input: 100, output: 10, cacheWrite: 40, cacheRead: 1000)
        // 100 × 1 + 10 × 5 + 40 × 1.25 + 1000 × 0.1, on Haiku (× 1).
        #expect(abs(UsageWeights.weight(tokens, model: "claude-haiku-5-5") - 300) < 1e-9)
    }

    @Test func modelsWeighByFamily() {
        let tokens = TokenCounts(input: 10)
        #expect(UsageWeights.weight(tokens, model: "claude-haiku-5-5") == 10)
        #expect(UsageWeights.weight(tokens, model: "claude-sonnet-5-5") == 30)
        #expect(UsageWeights.weight(tokens, model: "claude-opus-5-5") == 50)
        #expect(UsageWeights.weight(tokens, model: "claude-fable-5-1") == 50)
        #expect(UsageWeights.weight(tokens, model: "Claude-HAIKU-6") == 10)
    }

    @Test func anUnknownModelWeighsLikeOpus() {
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "something-new") == 50)
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "") == 50)
    }

    @Test func noTokensWeighNothing() {
        #expect(UsageWeights.weight(TokenCounts(), model: "claude-opus-5-5") == 0)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh UsageWeightsTests`
Expected: FAIL to compile: cannot find `TokenCounts` in scope.

- [ ] **Step 3: Implement**

`macos/Sources/Features/Usage/UsageWeights.swift`:

```swift
#if os(macOS)
import Foundation

/// One reply's or one run's tokens, by kind.
struct TokenCounts: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
}

/// How fast tokens use up a plan limit, relative to each other (usage
/// breakdown spec §1). A stand-in for API price, which Anthropic's limits
/// track; only the ratios matter. Fable counts like Opus until better known.
enum UsageWeights {
    static let input = 1.0
    static let output = 5.0
    static let cacheWrite = 1.25
    static let cacheRead = 0.1

    /// By the model id's family ("claude-haiku-5-5" → Haiku).
    static let families: [(name: String, weight: Double)] = [
        ("haiku", 1), ("sonnet", 3), ("opus", 5), ("fable", 5),
    ]
    static let otherModel = 5.0

    static func model(_ id: String) -> Double {
        let id = id.lowercased()
        return families.first { id.contains($0.name) }?.weight ?? otherModel
    }

    static func weight(_ tokens: TokenCounts, model id: String) -> Double {
        let raw = Double(tokens.input) * input + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite + Double(tokens.cacheRead) * cacheRead
        return raw * model(id)
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh UsageWeightsTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Usage/UsageWeights.swift macos/Tests/Usage/UsageWeightsTests.swift
git commit -m "lostty: usage: weigh tokens by kind and model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Lostty's Claude runs report their tokens

**Files:**
- Modify: `macos/Sources/Features/Branches/ClaudeCLI.swift` (`arguments` near line 25, `interpret` near line 50)
- Test: `macos/Tests/Branches/ClaudeCLITests.swift`

**Interfaces:**
- Consumes: `TokenCounts` (Task 1). The observer plan's Task 5 change to `ClaudeCLI.locate(command:shell:)` is already in this file; leave it as it is.
- Produces:
  - `ClaudeCLI.arguments` ends with `"--output-format", "json"`.
  - `struct ClaudeReply: Equatable, Sendable { var text: String; var isError: Bool; var usage: [String: TokenCounts] }`
  - `ClaudeCLI.parseReply(_ stdout: String) -> ClaudeReply?`
  - `ClaudeCLI.interpret(_:cancelled:) -> Result<String, SummaryError>` (same signature; reads the JSON's `result`).
  - `ClaudeCLI.usage(_ result: ProcessResult?) -> [String: TokenCounts]?` (nil without tokens).

- [ ] **Step 1: Write the failing tests**

Add to `ClaudeCLITests` (before the closing brace of the struct):

```swift
    @Test func asksForJSONSoRunsReportTheirTokens() {
        let args = ClaudeCLI.arguments
        #expect(args.firstIndex(of: "--output-format").map { args[$0 + 1] } == "json")
    }

    /// Trimmed from a real `claude -p --output-format json` run on Haiku.
    static let jsonRun = #"""
    {"type":"result","subtype":"success","is_error":false,"result":"  Adds X.\n","session_id":"s",
     "total_cost_usd":0.0006,"usage":{"input_tokens":2,"output_tokens":4},
     "modelUsage":{"claude-haiku-5-5":{"inputTokens":2,"outputTokens":4,"cacheReadInputTokens":649,
       "cacheCreationInputTokens":2995,"costUSD":0.0006}}}
    """#

    @Test func jsonOutputGivesTheTextAndTheTokens() {
        let result = ProcessResult(status: 0, stdout: Self.jsonRun, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .success("Adds X."))
        #expect(ClaudeCLI.usage(result)
            == ["claude-haiku-5-5": TokenCounts(input: 2, output: 4, cacheWrite: 2995, cacheRead: 649)])
    }

    @Test func aJSONErrorShowsItsTextAndStillCountsItsTokens() {
        let json = #"{"type":"result","is_error":true,"result":"Prompt is too long","#
            + #""modelUsage":{"claude-haiku-5-5":{"inputTokens":9,"outputTokens":0}}}"#
        let result = ProcessResult(status: 1, stdout: json, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Prompt is too long")))
        #expect(ClaudeCLI.usage(result) == ["claude-haiku-5-5": TokenCounts(input: 9)])
    }

    @Test func aJSONErrorWithNoTextNamesTheStatus() {
        let result = ProcessResult(status: 3, stdout: #"{"type":"result","is_error":true,"modelUsage":{}}"#, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude exited with status 3")))
        #expect(ClaudeCLI.usage(result) == nil)
    }

    @Test func anEmptyJSONResultIsAFailure() {
        let result = ProcessResult(status: 0, stdout: #"{"type":"result","is_error":false,"result":"  "}"#, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude returned nothing")))
    }

    @Test func plainOrBrokenOutputWorksAsBeforeWithNoTokens() {
        #expect(ClaudeCLI.usage(ProcessResult(status: 0, stdout: "Adds X.\n", stderr: "")) == nil)
        let broken = ProcessResult(status: 0, stdout: #"{"type":"res"#, stderr: "")
        #expect(ClaudeCLI.usage(broken) == nil)
        #expect(ClaudeCLI.interpret(broken, cancelled: false) == .success(#"{"type":"res"#))
        #expect(ClaudeCLI.usage(nil) == nil)
        // Another JSON object (the observer's notes, printed by a stand-in) is plain text.
        let notes = ProcessResult(status: 0, stdout: #"{"built":[],"just_now":"hi"}"#, stderr: "")
        #expect(ClaudeCLI.interpret(notes, cancelled: false) == .success(#"{"built":[],"just_now":"hi"}"#))
        #expect(ClaudeCLI.usage(notes) == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh ClaudeCLITests`
Expected: FAIL to compile: `ClaudeCLI` has no member `usage`.

- [ ] **Step 3: Implement**

In `ClaudeCLI.swift`, above `enum ClaudeCLI`, add:

```swift
/// What `claude -p --output-format json` prints: the answer, whether it is
/// an error, and the run's tokens per model.
struct ClaudeReply: Equatable, Sendable {
    var text: String
    var isError: Bool
    var usage: [String: TokenCounts]
}
```

Replace the `arguments` doc comment and value:

```swift
    /// Headless, cheap model, no tools, nothing saved, no MCP servers, and no
    /// user/project settings (so the user's hooks and plugins don't run).
    /// JSON output, so each run reports its tokens for the usage breakdown.
    static let arguments = [
        "-p", "--model", "haiku", "--tools", "", "--no-session-persistence",
        "--strict-mcp-config", "--setting-sources", "", "--output-format", "json",
    ]
```

Replace `interpret` with:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh ClaudeCLITests && macos/skins-test.sh BranchSummarizerTests && macos/skins-test.sh SummarizerTests`
Expected: all three `** TEST SUCCEEDED **` (the old plain-text tests still pass).

- [ ] **Step 5: Check the real shape once (tiny prompt)**

From the scratchpad directory, with Lostty's pane variables unset so the run's hooks can't report:

```bash
echo "Reply with the word ok." | env -u LOSTTY_SURFACE -u LOSTTY_SKINS_SURFACE -u LOSTTY_APP_PID -u LOSTTY_BIN \
  claude -p --model haiku --tools "" --no-session-persistence --strict-mcp-config --setting-sources "" \
  --output-format json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["type"], d["is_error"], repr(d["result"]), list(d["modelUsage"]))'
```

Expected: `result False 'ok' ['claude-haiku-…']`. If a key differs, fix `parseReply` and the fixture to match, and say so in the task report.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Branches/ClaudeCLI.swift macos/Tests/Branches/ClaudeCLITests.swift
git commit -m "lostty: usage: Lostty's Claude runs report their tokens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The usage ledger

**Files:**
- Create: `macos/Sources/Features/Usage/UsageLedger.swift`
- Test: `macos/Tests/Usage/UsageLedgerTests.swift`

**Interfaces:**
- Consumes: `TokenCounts` (Task 1); `TranscriptLocation(url:agent:)`, `TranscriptLocation.allowed(_:home:environment:)`, `TranscriptAgent.claude` (observer plan Task 3).
- Produces:
  - `enum LosttyRunSource: String, Codable, Sendable { case observer, branchSummary }`
  - `struct LosttyRun: Codable, Equatable, Sendable { var at: Date; var source: LosttyRunSource; var tokens: [String: TokenCounts] }`
  - `final class UsageLedger: @unchecked Sendable` with `static let shared`, `static let keep: TimeInterval` (8 days), `static var defaultURL: URL`, `init(url: URL)`, `reported(_ path: String, at: Date = Date(), locate: (String) -> TranscriptLocation? = …)`, `record(_ tokens: [String: TokenCounts], source: LosttyRunSource, at: Date = Date())`, `conversations(now: Date = Date()) -> [URL]`, `runs(now: Date = Date()) -> [LosttyRun]`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Usage/UsageLedgerTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageLedgerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString)/usage-ledger.json")
    }

    /// Every path passes, as Claude's.
    func claude(_ path: String) -> TranscriptLocation? {
        TranscriptLocation(url: URL(fileURLWithPath: path), agent: .claude)
    }

    @Test func keepsOnlyClaudeConversations() {
        let ledger = UsageLedger(url: tempURL())
        ledger.reported("/c/a.jsonl", at: now, locate: claude)
        ledger.reported("/x/rollout-1.jsonl", at: now,
                        locate: { TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .codex) })
        ledger.reported("/etc/passwd", at: now, locate: { _ in nil })
        // The real allow-list turns this away too.
        ledger.reported("/etc/passwd", at: now)
        #expect(ledger.conversations(now: now).map(\.path) == ["/c/a.jsonl"])
    }

    @Test func keepsTheResolvedPathOnce() {
        let ledger = UsageLedger(url: tempURL())
        let resolve: (String) -> TranscriptLocation? = { _ in
            TranscriptLocation(url: URL(fileURLWithPath: "/real/a.jsonl"), agent: .claude)
        }
        ledger.reported("/link/a.jsonl", at: now, locate: resolve)
        ledger.reported("/real/a.jsonl", at: now + 60, locate: resolve)
        #expect(ledger.conversations(now: now + 60).map(\.path) == ["/real/a.jsonl"])
    }

    @Test func recordsRunsAndSkipsEmptyOnes() {
        let ledger = UsageLedger(url: tempURL())
        ledger.record(["claude-haiku-5-5": TokenCounts(input: 5, output: 1)], source: .observer, at: now)
        ledger.record([:], source: .branchSummary, at: now)
        #expect(ledger.runs(now: now) == [
            LosttyRun(at: now, source: .observer, tokens: ["claude-haiku-5-5": TokenCounts(input: 5, output: 1)]),
        ])
    }

    @Test func dropsWhatsOlderThanEightDays() {
        let ledger = UsageLedger(url: tempURL())
        ledger.reported("/c/old.jsonl", at: now - 9 * day, locate: claude)
        ledger.record(["m": TokenCounts(input: 1)], source: .observer, at: now - 9 * day)
        ledger.reported("/c/new.jsonl", at: now - day, locate: claude)
        ledger.record(["m": TokenCounts(input: 2)], source: .branchSummary, at: now - day)
        #expect(ledger.conversations(now: now).map(\.path) == ["/c/new.jsonl"])
        #expect(ledger.runs(now: now).map(\.source) == [.branchSummary])
    }

    @Test func savesAndLoads() {
        let url = tempURL()
        let first = UsageLedger(url: url)
        first.reported("/c/a.jsonl", at: now, locate: claude)
        first.record(["m": TokenCounts(output: 3)], source: .branchSummary, at: now)
        let second = UsageLedger(url: url)
        #expect(second.conversations(now: now).map(\.path) == ["/c/a.jsonl"])
        #expect(second.runs(now: now) == first.runs(now: now))
    }

    @Test func anUnreadableFileReadsAsEmpty() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: url)
        let ledger = UsageLedger(url: url)
        #expect(ledger.conversations(now: now).isEmpty && ledger.runs(now: now).isEmpty)
        ledger.record(["m": TokenCounts(input: 1)], source: .observer, at: now)
        #expect(UsageLedger(url: url).runs(now: now).count == 1)
    }

    @Test func recordsFromManyThreadsAtOnce() {
        let ledger = UsageLedger(url: tempURL())
        let at = now
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            ledger.record(["m": TokenCounts(input: i + 1)], source: i % 2 == 0 ? .observer : .branchSummary, at: at)
        }
        #expect(ledger.runs(now: now).count == 50)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh UsageLedgerTests`
Expected: FAIL to compile: cannot find `UsageLedger` in scope.

- [ ] **Step 3: Implement**

`macos/Sources/Features/Usage/UsageLedger.swift`:

```swift
#if os(macOS)
import Foundation

/// What one of Lostty's own Claude runs was for.
enum LosttyRunSource: String, Codable, Sendable {
    case observer, branchSummary
}

/// One Claude run Lostty started by itself, and its tokens per model.
struct LosttyRun: Codable, Equatable, Sendable {
    var at: Date
    var source: LosttyRunSource
    var tokens: [String: TokenCounts]
}

/// The usage breakdown's memory across launches (usage breakdown spec §2,
/// §3): the Claude conversation files Lostty panes reported, and Lostty's
/// own runs. Paths and token counts only, never conversation text. Kept 8
/// days, a day past the weekly window. Safe from any thread: runs record
/// from the background threads they finish on.
final class UsageLedger: @unchecked Sendable {
    static let shared = UsageLedger(url: defaultURL)
    static let keep: TimeInterval = 8 * 24 * 3600

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/usage-ledger.json")
    }

    private struct Contents: Codable {
        /// Resolved conversation path → when a pane last reported it.
        var conversations: [String: Date] = [:]
        var runs: [LosttyRun] = []
    }

    private let url: URL
    private let lock = NSLock()
    private var contents: Contents

    /// An unreadable file reads as empty; the next change rewrites it.
    init(url: URL) {
        self.url = url
        contents = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(Contents.self, from: $0) } ?? Contents()
    }

    /// A pane's agent named its conversation file at a turn's end. Only
    /// Claude's own conversations count (TranscriptLocation decides what
    /// may be read); Codex's use another plan.
    func reported(
        _ path: String,
        at now: Date = Date(),
        locate: (String) -> TranscriptLocation? = { TranscriptLocation.allowed($0) }
    ) {
        guard let location = locate(path), location.agent == .claude else { return }
        change(now) { $0.conversations[location.url.path] = now }
    }

    /// One of Lostty's runs used `tokens` (from ClaudeCLI.usage).
    func record(_ tokens: [String: TokenCounts], source: LosttyRunSource, at now: Date = Date()) {
        guard !tokens.isEmpty else { return }
        change(now) { $0.runs.append(LosttyRun(at: now, source: source, tokens: tokens)) }
    }

    /// The conversation files reported in the last 8 days.
    func conversations(now: Date = Date()) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return contents.conversations.filter { now.timeIntervalSince($0.value) < Self.keep }
            .keys.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Lostty's runs in the last 8 days, oldest first.
    func runs(now: Date = Date()) -> [LosttyRun] {
        lock.lock()
        defer { lock.unlock() }
        return contents.runs.filter { now.timeIntervalSince($0.at) < Self.keep }
    }

    /// Edits, drops what's older than 8 days, and saves.
    private func change(_ now: Date, _ edit: (inout Contents) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        edit(&contents)
        contents.conversations = contents.conversations.filter { now.timeIntervalSince($0.value) < Self.keep }
        contents.runs.removeAll { now.timeIntervalSince($0.at) >= Self.keep }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(contents) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh UsageLedgerTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Usage/UsageLedger.swift macos/Tests/Usage/UsageLedgerTests.swift
git commit -m "lostty: usage: keep reported conversations and Lostty's runs for 8 days

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Record Lostty's runs and the panes' conversations

**Files:**
- Modify: `macos/Sources/Features/Branches/BranchSummarizer.swift` (`run`, near line 30)
- Modify: `macos/Sources/Features/Observer/Summarizer.swift` (`run` and `runClaude`, from observer plan Task 5)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (the `ClaudeRuntime.shared.turnEnded = …` line from observer plan Task 7)
- Test: `macos/Tests/Branches/BranchSummarizerTests.swift`, `macos/Tests/Observer/SummarizerTests.swift`

**Interfaces:**
- Consumes: `ClaudeCLI.usage(_:)` (Task 2); `UsageLedger.record/reported`, `LosttyRunSource` (Task 3); `Summarizer.run(_:prompt:handle:)`, `Summarizer.runClaude`, `Summarizer.runCodex`, the `script(_:_:)` test helper in `SummarizerTests` (observer plan Task 5); `ClaudeRuntime.turnEnded`, `TurnObserver.shared.turnEnded(pane:path:)` (observer plan Tasks 2, 6, 7).
- Produces:
  - `BranchSummarizer.run(branch:base:root:claude:handle:ledger: UsageLedger = .shared)`
  - `Summarizer.run(_ kind: SummarizerKind, prompt: String, handle: RunHandle, ledger: UsageLedger = .shared) async -> Result<String, SummaryError>` (existing callers, including `TurnObserver.Dependencies.live`, don't change).

- [ ] **Step 1: Write the failing tests**

Add to `BranchSummarizerTests`:

```swift
    @Test func recordsTheRunsTokens() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude(
            #"echo '{"type":"result","is_error":false,"result":"Adds feat one.","modelUsage":{"claude-haiku-5-5":{"inputTokens":10,"outputTokens":2}}}'"#)
        let ledger = UsageLedger(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString).json"))
        let result = BranchSummarizer.run(
            branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle(), ledger: ledger)
        #expect(result == .success("Adds feat one."))
        #expect(ledger.runs().map(\.source) == [.branchSummary])
        #expect(ledger.runs().first?.tokens == ["claude-haiku-5-5": TokenCounts(input: 10, output: 2)])
    }

    @Test func plainOutputRecordsNothing() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo 'Adds feat one.'")
        let ledger = UsageLedger(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString).json"))
        _ = BranchSummarizer.run(
            branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle(), ledger: ledger)
        #expect(ledger.runs().isEmpty)
    }
```

Add to `SummarizerTests`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh BranchSummarizerTests`
Expected: FAIL to compile: extra argument `ledger` in call.

- [ ] **Step 3: Record branch summaries**

In `BranchSummarizer.swift`, change the `run` signature and its last lines:

```swift
    static func run(
        branch: String, base: String, root: String, claude: String, handle: RunHandle,
        ledger: UsageLedger = .shared
    ) -> Result<String, SummaryError> {
```

and replace `return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)` with:

```swift
        if let tokens = ClaudeCLI.usage(result) { ledger.record(tokens, source: .branchSummary) }
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
```

- [ ] **Step 4: Record the observer's Claude runs**

In `Summarizer.swift`, change `run`'s signature and its `.claude` case:

```swift
    static func run(
        _ kind: SummarizerKind, prompt: String, handle: RunHandle, ledger: UsageLedger = .shared
    ) async -> Result<String, SummaryError> {
        switch kind {
        case .claude(let path):
            return await Task.detached(priority: .utility) {
                Summarizer.runClaude(path, prompt: prompt, handle: handle, ledger: ledger)
            }.value
```

(the `.codex`, `.apple` and `.none` cases stay as they are), and `runClaude` becomes:

```swift
    private static func runClaude(
        _ path: String, prompt: String, handle: RunHandle, ledger: UsageLedger
    ) -> Result<String, SummaryError> {
        let result = ProcessRunner.run(
            path, ClaudeCLI.arguments, cwd: NSTemporaryDirectory(), environment: environment(for: path),
            inheritEnvironment: false, stdin: prompt, timeout: ClaudeCLI.timeout, onStart: handle.started)
        if let tokens = ClaudeCLI.usage(result) { ledger.record(tokens, source: .observer) }
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
    }
```

- [ ] **Step 5: Report each turn's conversation to the ledger**

In `AppDelegate.swift`, replace:

```swift
        ClaudeRuntime.shared.turnEnded = { TurnObserver.shared.turnEnded(pane: $0, path: $1) }
```

with:

```swift
        ClaudeRuntime.shared.turnEnded = { pane, path in
            TurnObserver.shared.turnEnded(pane: pane, path: path)
            // The usage breakdown counts this conversation as Claude Code in Lostty.
            UsageLedger.shared.reported(path)
        }
```

- [ ] **Step 6: Run the tests and build**

Run: `macos/skins-test.sh BranchSummarizerTests && macos/skins-test.sh SummarizerTests && macos/skins-test.sh TurnObserverTests && macos/build.nu`
Expected: three `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Branches/BranchSummarizer.swift macos/Sources/Features/Observer/Summarizer.swift \
  macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Branches/BranchSummarizerTests.swift \
  macos/Tests/Observer/SummarizerTests.swift
git commit -m "lostty: usage: record Lostty's runs and the panes' conversations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Counting Claude Code's replies

**Files:**
- Create: `macos/Sources/Features/Usage/UsageCounter.swift`
- Test: `macos/Tests/Usage/UsageCounterTests.swift`

**Interfaces:**
- Consumes: `TokenCounts`, `UsageWeights.weight` (Task 1); `LosttyRun` (Task 3).
- Produces:
  - `enum UsagePart: Equatable, Sendable { case claudeCode, lostty }`
  - `struct WeightedUse: Equatable, Sendable { var at: Date; var part: UsagePart; var weight: Double }`
  - `actor UsageCounter` with `init(chunk: Int = 8 << 20)`, `count(_ conversations: [URL], since: Date) -> [WeightedUse]`, and statics `withSubagents(_ file: URL) -> [URL]`, `date(_ stamp: String) -> Date?`, `uses(of runs: [LosttyRun], since: Date) -> [WeightedUse]`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Usage/UsageCounterTests.swift`:

```swift
#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Lostty

struct UsageCounterTests {
    let now = Date()
    var since: Date { now - 7 * 24 * 3600 }

    func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// One line of a reply, the way Claude Code writes them: a reply with
    /// several content items is several lines with the same id and tokens.
    func reply(_ id: String, at: Date? = nil, model: String = "claude-haiku-5-5", input: Int = 10,
               content: String = "text") -> String {
        let at = stamp(at ?? now - 3600)
        return #"{"type":"assistant","timestamp":"\#(at)","requestId":"req-\#(id)","isSidechain":false,"#
            + #""message":{"id":"msg-\#(id)","model":"\#(model)","content":[{"type":"\#(content)"}],"#
            + #""usage":{"input_tokens":\#(input),"output_tokens":0,"cache_creation_input_tokens":0,"#
            + #""cache_read_input_tokens":0}}}"#
    }

    let prompt = #"{"type":"user","timestamp":"2026-10-14T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#

    func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func write(_ lines: [String], to url: URL, newline: Bool = true) throws {
        try Data((lines.joined(separator: "\n") + (newline ? "\n" : "")).utf8).write(to: url)
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func aReplyOnSeveralLinesCountsOnce() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([prompt, reply("a", content: "thinking"), reply("a", content: "text"), reply("a", content: "tool_use"),
                   reply("b", input: 20)], to: file)
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.count == 2)
        #expect(uses.map(\.weight).sorted() == [10, 20])
        #expect(uses.allSatisfy { $0.part == .claudeCode })
    }

    @Test func repliesBeforeTheWindowDontCount() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("old", at: since - 60), reply("new")], to: file)
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.count == 1)
    }

    @Test func timestampsWithOrWithoutFractionsCount() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        let plain = (now - 60).formatted(Date.ISO8601FormatStyle())
        let withoutFraction = reply("a").replacingOccurrences(of: stamp(now - 3600), with: plain)
        try write([withoutFraction, reply("b")], to: file)
        #expect(await UsageCounter().count([file], since: since).count == 2)
        #expect(UsageCounter.date("2026-10-12T05:45:50.990Z") != nil)
        #expect(UsageCounter.date("2026-10-12T05:45:50Z") != nil)
        #expect(UsageCounter.date("yesterday") == nil)
    }

    @Test func subagentsCountWithTheirConversation() async throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("s.jsonl")
        try write([reply("a")], to: file)
        let subagents = dir.appendingPathComponent("s/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try write([reply("sub", model: "claude-sonnet-5-5")], to: subagents.appendingPathComponent("agent-1.jsonl"))
        try write(["{}"], to: subagents.appendingPathComponent("agent-1.meta.json"))
        #expect(UsageCounter.withSubagents(file).map(\.lastPathComponent) == ["s.jsonl", "agent-1.jsonl"])
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.map(\.weight).sorted() == [10, 30])
    }

    @Test func aHalfWrittenLineWaitsAndNothingCountsTwice() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a"), reply("b")], to: file, newline: false)
        let counter = UsageCounter()
        #expect(await counter.count([file], since: since).count == 1)
        try append("\n" + reply("c") + "\n", to: file)
        #expect(await counter.count([file], since: since).count == 3)
        #expect(await counter.count([file], since: since).count == 3)
    }

    @Test func aSmallChunkSizeCountsTheSame() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write((0..<40).map { reply("r\($0)") } + [prompt], to: file)
        // Chunks far shorter than a line: every line spans several reads.
        #expect(await UsageCounter(chunk: 37).count([file], since: since).count == 40)
    }

    @Test func aFileThatShrankStartsOver() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a"), reply("b"), reply("c")], to: file)
        let counter = UsageCounter()
        #expect(await counter.count([file], since: since).count == 3)
        try write([reply("d", input: 40)], to: file)
        let uses = await counter.count([file], since: since)
        #expect(uses.map(\.weight) == [40])
    }

    @Test func aFileUntouchedThisWeekIsSkipped() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a")], to: file)
        try FileManager.default.setAttributes([.modificationDate: since - 3600], ofItemAtPath: file.path)
        #expect(await UsageCounter().count([file], since: since).isEmpty)
    }

    @Test func aMissingFileOrAFifoIsSkipped() async throws {
        let dir = try folder()
        let fifo = dir.appendingPathComponent("pipe.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let missing = dir.appendingPathComponent("missing.jsonl")
        #expect(await UsageCounter().count([fifo, missing], since: since).isEmpty)
    }

    @Test func losttysRunsWeighEveryModelTheyUsed() {
        let runs = [
            LosttyRun(at: now - 60, source: .observer,
                      tokens: ["claude-haiku-5-5": TokenCounts(input: 10), "claude-sonnet-5-5": TokenCounts(input: 1)]),
            LosttyRun(at: since - 60, source: .branchSummary, tokens: ["claude-haiku-5-5": TokenCounts(input: 99)]),
        ]
        let uses = UsageCounter.uses(of: runs, since: since)
        #expect(uses == [WeightedUse(at: now - 60, part: .lostty, weight: 13)])
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh UsageCounterTests`
Expected: FAIL to compile: cannot find `UsageCounter` in scope.

- [ ] **Step 3: Implement**

`macos/Sources/Features/Usage/UsageCounter.swift`:

```swift
#if os(macOS)
import Foundation

/// Which part of the usage breakdown a use belongs to.
enum UsagePart: Equatable, Sendable {
    case claudeCode, lostty
}

/// One reply's or run's weighted tokens, and when it happened.
struct WeightedUse: Equatable, Sendable {
    var at: Date
    var part: UsagePart
    var weight: Double
}

/// Counts the replies in Lostty panes' Claude conversation files and their
/// subagents' files (usage breakdown spec §4). An actor, so reading runs
/// off the main thread; it remembers how far it read each file, so a
/// count after the first reads only what was added.
actor UsageCounter {
    /// One reply as counted.
    struct Reply: Equatable, Sendable {
        var at: Date
        var weight: Double
    }

    private struct FileState {
        var offset: UInt64 = 0
        /// By `message.id` and `requestId`: one reply is written on several
        /// lines, each with the same id and tokens.
        var replies: [String: Reply] = [:]
    }

    private var files: [String: FileState] = [:]
    private let chunk: Int

    /// `chunk`: how much is read at a time, so a huge file is never in
    /// memory all at once.
    init(chunk: Int = 8 << 20) {
        self.chunk = chunk
    }

    /// Every reply since `since` in `conversations` and their subagents.
    func count(_ conversations: [URL], since: Date) -> [WeightedUse] {
        var uses: [WeightedUse] = []
        var seen: Set<String> = []
        for file in conversations.flatMap(Self.withSubagents) {
            let path = file.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            var state = files[path] ?? FileState()
            read(file, into: &state, since: since)
            state.replies = state.replies.filter { $0.value.at >= since }
            files[path] = state
            uses += state.replies.values.map { WeightedUse(at: $0.at, part: .claudeCode, weight: $0.weight) }
        }
        // Files no longer reported are forgotten.
        files = files.filter { seen.contains($0.key) }
        return uses
    }

    /// A conversation file and its subagents' files,
    /// `<file without .jsonl>/subagents/*.jsonl`.
    static func withSubagents(_ file: URL) -> [URL] {
        let folder = file.deletingPathExtension().appendingPathComponent("subagents")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return [file] + names.filter { $0.hasSuffix(".jsonl") }.sorted().map { folder.appendingPathComponent($0) }
    }

    /// Claude Code's timestamps, with or without fractional seconds.
    static func date(_ stamp: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp))
            ?? (try? Date.ISO8601FormatStyle().parse(stamp))
    }

    /// Lostty's runs since `since`, each weighing every model it used.
    static func uses(of runs: [LosttyRun], since: Date) -> [WeightedUse] {
        runs.filter { $0.at >= since }.map { run in
            WeightedUse(at: run.at, part: .lostty,
                        weight: run.tokens.reduce(0) { $0 + UsageWeights.weight($1.value, model: $1.key) })
        }
    }

    /// Reads `file` past `state.offset`, whole lines only: a half-written
    /// last line waits for next time.
    private func read(_ file: URL, into state: inout FileState, since: Date) {
        // Regular files only: a FIFO named *.jsonl would block the read.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            state = FileState()
            return
        }
        // Not written this week: nothing in it can count.
        if let modified = attributes[.modificationDate] as? Date, modified < since {
            state = FileState()
            return
        }
        // Shorter than what was read: the file was replaced; start over.
        if size < state.offset { state = FileState() }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil else { return }
        var pending = Data()
        while let data = try? handle.read(upToCount: chunk), !data.isEmpty {
            pending.append(data)
            guard let end = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let lines = pending[pending.startIndex...end]
            Self.parse(lines, into: &state.replies, since: since)
            state.offset += UInt64(lines.count)
            pending = Data(pending[pending.index(after: end)...])
        }
    }

    /// Adds the replies in complete `lines` to `replies`, once each.
    static func parse(_ lines: Data, into replies: inout [String: Reply], since: Date) {
        let usageKey = Data(#""usage""#.utf8)
        for line in lines.split(separator: UInt8(ascii: "\n")) {
            // Most lines are prompts and tool output: skip them before parsing.
            guard line.range(of: usageKey) != nil,
                  let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let id = message["id"] as? String ?? object["uuid"] as? String,
                  let stamp = object["timestamp"] as? String, let at = date(stamp), at >= since
            else { continue }
            func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let tokens = TokenCounts(
                input: int("input_tokens"), output: int("output_tokens"),
                cacheWrite: int("cache_creation_input_tokens"), cacheRead: int("cache_read_input_tokens"))
            let weight = UsageWeights.weight(tokens, model: message["model"] as? String ?? "")
            guard weight > 0 else { continue }
            replies[id + "\n" + (object["requestId"] as? String ?? "")] = Reply(at: at, weight: weight)
        }
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh UsageCounterTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Usage/UsageCounter.swift macos/Tests/Usage/UsageCounterTests.swift
git commit -m "lostty: usage: count each Claude Code reply once, reading only what's new

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Splitting a limit

**Files:**
- Create: `macos/Sources/Features/Usage/UsageBreakdown.swift`
- Test: `macos/Tests/Usage/UsageBreakdownTests.swift`

**Interfaces:**
- Consumes: `WeightedUse`, `UsagePart` (Task 5); `ClaudeUsageReport.Limit` (existing, `ClaudeUsage.swift`: `percent`, `resetsAt`, `percent(at:)`).
- Produces: `struct UsageBreakdown: Equatable { var claudeCode: Double; var lostty: Double; static let session: TimeInterval; static let week: TimeInterval; static func make(limit:length:uses:now:) -> UsageBreakdown?; var text: String }`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Usage/UsageBreakdownTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageBreakdownTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600

    func use(_ part: UsagePart, _ weight: Double, hoursAgo: Double = 1) -> WeightedUse {
        WeightedUse(at: now - hoursAgo * hour, part: part, weight: weight)
    }

    @Test func thePartsSplitThePercentageByWeight() throws {
        let limit = ClaudeUsageReport.Limit(percent: 42, resetsAt: now + 2 * hour)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.claudeCode, 900), use(.lostty, 100), use(.claudeCode, 50)], now: now))
        #expect(abs(split.claudeCode + split.lostty - 42) < 1e-9)
        #expect(abs(split.lostty - 42 * 100 / 1050) < 1e-9)
    }

    @Test func theWindowEndsAtTheReset() throws {
        // Session resets in 2 h, so it began 3 h ago: older uses don't count.
        let limit = ClaudeUsageReport.Limit(percent: 10, resetsAt: now + 2 * hour)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.claudeCode, 100, hoursAgo: 2), use(.lostty, 100, hoursAgo: 4)], now: now))
        #expect(split == UsageBreakdown(claudeCode: 10, lostty: 0))
    }

    @Test func withoutAResetTimeTheWindowEndsNow() throws {
        let limit = ClaudeUsageReport.Limit(percent: 10, resetsAt: nil)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.lostty, 100, hoursAgo: 4), use(.claudeCode, 100, hoursAgo: 6)], now: now))
        #expect(split == UsageBreakdown(claudeCode: 0, lostty: 10))
    }

    @Test func noLimitOrAResetLimitHasNoBreakdown() {
        let uses = [use(.claudeCode, 100)]
        #expect(UsageBreakdown.make(limit: nil, length: UsageBreakdown.session, uses: uses, now: now) == nil)
        let reset = ClaudeUsageReport.Limit(percent: 42, resetsAt: now - 60)
        #expect(UsageBreakdown.make(limit: reset, length: UsageBreakdown.session, uses: uses, now: now) == nil)
        let zero = ClaudeUsageReport.Limit(percent: 0.4, resetsAt: now + hour)
        #expect(UsageBreakdown.make(limit: zero, length: UsageBreakdown.session, uses: uses, now: now) == nil)
    }

    @Test func nothingCountedHasNoBreakdown() {
        let limit = ClaudeUsageReport.Limit(percent: 42, resetsAt: now + hour)
        #expect(UsageBreakdown.make(limit: limit, length: UsageBreakdown.session, uses: [], now: now) == nil)
        #expect(UsageBreakdown.make(limit: limit, length: UsageBreakdown.session,
                                    uses: [use(.claudeCode, 100, hoursAgo: 30)], now: now) == nil)
    }

    @Test func theTextAddsUpToTheShownPercentage() {
        #expect(UsageBreakdown(claudeCode: 40.6, lostty: 1.4).text == "Claude Code ≈ 41 · Lostty ≈ 1")
        #expect(UsageBreakdown(claudeCode: 41.4, lostty: 0.4).text == "Claude Code ≈ 42 · Lostty <1")
        #expect(UsageBreakdown(claudeCode: 0.3, lostty: 9.7).text == "Claude Code <1 · Lostty ≈ 10")
        #expect(UsageBreakdown(claudeCode: 17, lostty: 0).text == "Claude Code ≈ 17 · Lostty ≈ 0")
        #expect(UsageBreakdown(claudeCode: 40.5, lostty: 0.5).text == "Claude Code ≈ 40 · Lostty ≈ 1")
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh UsageBreakdownTests`
Expected: FAIL to compile: cannot find `UsageBreakdown` in scope.

- [ ] **Step 3: Implement**

`macos/Sources/Features/Usage/UsageBreakdown.swift`:

```swift
#if os(macOS)
import Foundation

/// One limit's percentage split between Claude Code and Lostty by weighted
/// tokens (usage breakdown spec §1), in percentage points. An estimate:
/// use Lostty can't see is folded into the two parts.
struct UsageBreakdown: Equatable {
    var claudeCode: Double
    var lostty: Double

    static let session: TimeInterval = 5 * 3600
    static let week: TimeInterval = 7 * 24 * 3600

    /// The split of `limit` over its window, `[resetsAt − length, now]`
    /// (`now − length` without a reset time). Nil without a limit, while it
    /// shows 0% (or has reset), and with nothing counted in the window.
    static func make(
        limit: ClaudeUsageReport.Limit?, length: TimeInterval, uses: [WeightedUse], now: Date
    ) -> UsageBreakdown? {
        guard let limit else { return nil }
        let percent = limit.percent(at: now)
        guard Int(percent.rounded()) > 0 else { return nil }
        let start = (limit.resetsAt ?? now) - length
        var code = 0.0
        var lostty = 0.0
        for use in uses where use.at >= start && use.at <= now {
            switch use.part {
            case .claudeCode: code += use.weight
            case .lostty: lostty += use.weight
            }
        }
        let total = code + lostty
        guard total > 0 else { return nil }
        return UsageBreakdown(claudeCode: percent * code / total, lostty: percent * lostty / total)
    }

    /// "Claude Code ≈ 41 · Lostty ≈ 1": whole points that add up to the
    /// percentage the row shows; a part under half a point is "<1".
    var text: String {
        let total = Int((claudeCode + lostty).rounded())
        let lostty = min(Int(self.lostty.rounded()), total)
        let code = total - lostty
        func part(_ name: String, _ points: Double, _ whole: Int) -> String {
            points > 0 && points < 0.5 ? "\(name) <1" : "\(name) ≈ \(whole)"
        }
        return part("Claude Code", claudeCode, code) + " · " + part("Lostty", self.lostty, lostty)
    }
}
#endif
```

Check the `40.5 / 0.5` case by hand: total = 41, lostty = 1 (0.5 rounds away from zero), code = 40. The `0.3 / 9.7` case: total = 10, lostty = 10, code = 0, and 0.3 < 0.5 so "Claude Code <1".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh UsageBreakdownTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Usage/UsageBreakdown.swift macos/Tests/Usage/UsageBreakdownTests.swift
git commit -m "lostty: usage: split a limit between Claude Code and Lostty

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The breakdown in the usage popover

**Files:**
- Create: `macos/Sources/Features/Usage/UsageBreakdownRuntime.swift`
- Modify: `macos/Sources/Features/Claude/ClaudeUsageBar.swift` (`ClaudeUsageDetails`, near line 155)
- Test: `macos/Tests/Usage/UsageBreakdownRuntimeTests.swift`

**Interfaces:**
- Consumes: `UsageLedger` (Task 3); `UsageCounter`, `WeightedUse` (Task 5); `UsageBreakdown` (Task 6); `ClaudeUsageRuntime` (`fiveHour`, `sevenDay`, `userVarChanged`, `init(defaults:now:)`) and `ClaudeUsageMetric` (existing).
- Produces: `@MainActor final class UsageBreakdownRuntime: ObservableObject` with `static let shared`, `static let reuse: TimeInterval` (60), `static let counting`, `static let footnote`, `init(ledger:counter:now:)`, `@Published private(set) var uses: [WeightedUse]?`, `@Published private(set) var isCounting: Bool`, `@discardableResult func refresh() -> Task<Void, Never>?`, `func breakdown(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> UsageBreakdown?`, `func line(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> String?`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Usage/UsageBreakdownRuntimeTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct UsageBreakdownRuntimeTests {
    final class Clock {
        var now = Date()
    }

    let pane = UUID()

    func makeDefaults() -> UserDefaults {
        let name = "UsageBreakdownRuntimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A conversation with one Opus reply (weight 50) an hour ago, reported
    /// to a fresh ledger that also holds one Haiku run (weight 50).
    func setUp(_ clock: Clock) throws -> (UsageBreakdownRuntime, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ubr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        let at = (clock.now - 3600).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        try Data((#"{"type":"assistant","timestamp":"\#(at)","requestId":"r","message":{"id":"m","#
            + #""model":"claude-opus-5-5","usage":{"input_tokens":10}}}"# + "\n").utf8).write(to: file)
        let ledger = UsageLedger(url: dir.appendingPathComponent("ledger.json"))
        ledger.reported(file.path, at: clock.now, locate: { TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .claude) })
        ledger.record(["claude-haiku-5-5": TokenCounts(input: 50)], source: .observer, at: clock.now - 60)
        return (UsageBreakdownRuntime(ledger: ledger, counter: UsageCounter(), now: { clock.now }), file)
    }

    func usage(_ clock: Clock, session: Double = 42, week: Double = 17) -> ClaudeUsageRuntime {
        let usage = ClaudeUsageRuntime(defaults: makeDefaults(), now: { clock.now })
        let reset = Int(clock.now.timeIntervalSince1970) + 3600
        usage.userVarChanged(pane, name: "LOSTTY_USAGE", value:
            #"{"v":1,"five":{"pct":\#(session),"reset":\#(reset)},"week":{"pct":\#(week),"reset":\#(reset + 86400)}}"#)
        return usage
    }

    @Test func countsThenSplitsEachLimit() async throws {
        let clock = Clock()
        let (runtime, _) = try setUp(clock)
        let usage = usage(clock)
        #expect(runtime.line(.session, usage: usage) == nil)
        let task = runtime.refresh()
        #expect(runtime.isCounting)
        #expect(runtime.line(.session, usage: usage) == UsageBreakdownRuntime.counting)
        await task?.value
        #expect(!runtime.isCounting)
        #expect(runtime.line(.session, usage: usage) == "Claude Code ≈ 21 · Lostty ≈ 21")
        #expect(runtime.line(.weekly, usage: usage) == "Claude Code ≈ 8 · Lostty ≈ 9")
        #expect(runtime.line(.weeklyFable, usage: usage) == nil)
    }

    @Test func aCountIsReusedForAMinute() async throws {
        let clock = Clock()
        let (runtime, file) = try setUp(clock)
        await runtime.refresh()?.value
        // A new reply doesn't show until the minute is up.
        let at = clock.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"type":"assistant","timestamp":"\#(at)","requestId":"r2","#
            + #""message":{"id":"m2","model":"claude-opus-5-5","usage":{"input_tokens":10}}}"# + "\n").utf8))
        try handle.close()
        #expect(runtime.refresh() == nil)
        #expect(runtime.uses?.count == 2)
        clock.now += 61
        await runtime.refresh()?.value
        #expect(runtime.uses?.count == 3)
    }

    @Test func noLimitReportMeansNoLine() async throws {
        let clock = Clock()
        let (runtime, _) = try setUp(clock)
        await runtime.refresh()?.value
        let empty = ClaudeUsageRuntime(defaults: makeDefaults(), now: { clock.now })
        #expect(runtime.line(.session, usage: empty) == nil)
        #expect(runtime.line(.weekly, usage: empty) == nil)
    }
}
#endif
```

The expected numbers: the Opus reply weighs 10 × 5 = 50 and the Haiku run 50 × 1 = 50, so each part gets half. Session 42 → 21 · 21. Weekly 17 → 8.5 · 8.5, which `text` shows as total 17, Lostty 9 (8.5 rounds away from zero), Claude Code 8.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh UsageBreakdownRuntimeTests`
Expected: FAIL to compile: cannot find `UsageBreakdownRuntime` in scope.

- [ ] **Step 3: Implement the runtime**

`macos/Sources/Features/Usage/UsageBreakdownRuntime.swift`:

```swift
#if os(macOS)
import Combine
import Foundation

/// The usage popover's breakdown: counts when the popover opens (reusing a
/// count for a minute), and words each limit's line.
@MainActor
final class UsageBreakdownRuntime: ObservableObject {
    static let shared = UsageBreakdownRuntime()
    static let reuse: TimeInterval = 60
    static let counting = "Counting…"
    static let footnote = "Estimated from Claude use in Lostty."

    /// Everything counted in the last week; nil before the first count.
    @Published private(set) var uses: [WeightedUse]?
    @Published private(set) var isCounting = false

    private let ledger: UsageLedger
    private let counter: UsageCounter
    private let now: () -> Date
    private var countedAt: Date?

    init(ledger: UsageLedger = .shared, counter: UsageCounter = UsageCounter(), now: @escaping () -> Date = Date.init) {
        self.ledger = ledger
        self.counter = counter
        self.now = now
    }

    /// Counts again, unless a count is under way or under a minute old
    /// (then nil). The count runs on the counter actor, off the main thread.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        let now = self.now()
        guard !isCounting else { return nil }
        if let countedAt, now.timeIntervalSince(countedAt) < Self.reuse { return nil }
        isCounting = true
        let since = now - UsageBreakdown.week
        let conversations = ledger.conversations(now: now)
        let runs = ledger.runs(now: now)
        let counter = counter
        return Task {
            let code = await counter.count(conversations, since: since)
            self.uses = code + UsageCounter.uses(of: runs, since: since)
            self.countedAt = now
            self.isCounting = false
        }
    }

    func breakdown(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> UsageBreakdown? {
        guard let uses else { return nil }
        switch metric {
        case .session:
            return UsageBreakdown.make(limit: usage.fiveHour, length: UsageBreakdown.session, uses: uses, now: now())
        case .weekly:
            return UsageBreakdown.make(limit: usage.sevenDay, length: UsageBreakdown.week, uses: uses, now: now())
        case .weeklyFable:
            return nil
        }
    }

    /// The row's breakdown line: the split, "Counting…" during the first
    /// count, or nil (no limit report, nothing counted, Weekly · Fable).
    func line(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> String? {
        if uses == nil {
            return isCounting && metric != .weeklyFable && usage.percent(metric) != nil ? Self.counting : nil
        }
        return breakdown(metric, usage: usage)?.text
    }
}
#endif
```

- [ ] **Step 4: Show it in the popover**

In `ClaudeUsageBar.swift`, `ClaudeUsageDetails` gains the runtime, the lines, the footnote, and a count on opening. Replace the struct's stored properties and `body`:

```swift
private struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageRuntime
    let accent: Color
    @ObservedObject var breakdown: UsageBreakdownRuntime = .shared
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClaudeUsageMetric.allCases) { metric in
                row(metric)
            }
            if ClaudeUsageMetric.allCases.contains(where: { breakdown.line($0, usage: usage) != nil }) {
                Text(UsageBreakdownRuntime.footnote)
                    .font(ClaudeUsageFont.font(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
        }
        .font(ClaudeUsageFont.font(size: 12))
        .padding(6)
        .frame(width: 320)
        .onAppear { breakdown.refresh() }
    }
```

and in `row(_:)`, right after the `Text(subtitle(metric))` block (its `.font` and `.foregroundStyle` lines), inside the same `VStack`:

```swift
                if let line = breakdown.line(metric, usage: usage) {
                    Text(line)
                        .font(ClaudeUsageFont.font(size: 10))
                        .foregroundStyle(.secondary)
                }
```

The existing call `ClaudeUsageDetails(usage: usage, accent: accent) { showingDetails = false }` keeps compiling: `breakdown` has a default and `dismiss` is still the trailing closure.

- [ ] **Step 5: Run the tests and build**

Run: `macos/skins-test.sh UsageBreakdownRuntimeTests && macos/skins-test.sh ClaudeUsageTests && macos/build.nu`
Expected: both suites `** TEST SUCCEEDED **`; `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Usage/UsageBreakdownRuntime.swift macos/Sources/Features/Claude/ClaudeUsageBar.swift \
  macos/Tests/Usage/UsageBreakdownRuntimeTests.swift
git commit -m "lostty: usage: show the breakdown under each limit in the usage popover

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The real thing, on this Mac (with the user)

No code. Ask the user before installing anything: "The usage breakdown is built and its tests pass. Want me to install it with `macos/install-skins.sh`? You'd then switch with menu bar → Restart to Update." Install only on a yes, and never quit Lostty.

- [ ] **Step 1: After the user restarts into the new build,** they finish a Claude turn in a pane or two (a conversation only counts once it has ended a turn on this build), then click the usage bar. Expected: under Current session and Weekly · all models, a line like "Claude Code ≈ 41 · Lostty ≈ 1", "Counting…" for a moment the first time, and the footnote "Estimated from Claude use in Lostty." Weekly · Fable has no line.
- [ ] **Step 2: The parts add up:** each line's two numbers add up to the percentage on its row.
- [ ] **Step 3: Lostty's own use grows:** in the Branches extension, summarize a branch, wait a minute, reopen the popover. Expected: the Lostty number is the same or higher. `~/Library/Application Support/Lostty/usage-ledger.json` has a `branchSummary` run.
- [ ] **Step 4: Opening the popover stays smooth** with several long conversations: the window doesn't stall.
- [ ] **Step 5: Report** what the user saw, and any number that looked wrong, before calling the plan done.
