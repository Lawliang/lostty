# Branches Sidebar App and Sidebar Auto-Hide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Branches" app in the window's right sidebar that widens the sidebar into a panel showing the focused pane's repo, its local branches, which Lostty sessions (and agents) are on each, git facts and on-demand Claude summaries — plus a setting that auto-hides the sidebar strip when no app is open.

**Architecture:** Pure, tested units under `macos/Sources/Features/Branches/` (git runner, parsers, repo reader, session placement, section building, summary cache/prompt/CLI) feed a per-window `BranchesModel` with an injectable environment; SwiftUI views render it in a new "sidebar" presentation slot of the existing extensions sidebar. Auto-hide is a pure state machine driven by hover, read from a `UserDefaults.ghostty` preference set in a new Lostty Settings window.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, macOS 13 deployment target, Combine, FSEvents, Swift Testing, `/usr/bin/git`, `claude -p`.

**Spec:** `docs/superpowers/specs/2026-10-12-branches-sidebar-design.md`

## Global Constraints

- macOS deployment target 13.0: no macOS 14-only SwiftUI APIs without `#available` (use the one-parameter `.onChange(of:) { newValue in }`, `.onExitCommand`, `Backport`).
- Swift 5 language mode (the app target's `SWIFT_VERSION = 5.0`).
- New source files are picked up automatically (the Xcode project uses synchronized folders for `macos/Sources` and `macos/Tests`); never edit `project.pbxproj`.
- Every file is wrapped in `#if os(macOS)` … `#endif` like its neighbours.
- Run a test suite: `macos/skins-test.sh <SuiteName>` (prints failures; exits non-zero on failure). It needs `macos/GhosttyKit.xcframework`, which exists; if it is missing run `zig build -Demit-macos-app=false` first.
- Git is run as `/usr/bin/git -C <dir> …` with `GIT_OPTIONAL_LOCKS=0`; every call has a timeout.
- Preferences key: `LosttySidebarAutoHide` in `UserDefaults.ghostty`, default `false`.
- Panel width 340pt; strip width stays `ExtensionSidebarView.width` (64pt); auto-hide reveal edge 4pt; hide delay 0.5s.
- "Older" = last commit more than 30 days ago. Base = `origin/HEAD`'s branch if it exists locally, else `main`, else `master`.
- Summaries: `claude -p --model haiku --tools "" --no-session-persistence --strict-mcp-config --setting-sources ""`, prompt on stdin, 60s timeout, prompt capped at 60,000 bytes. Never run automatically. No automated test calls the real `claude`.
- Never stage `src/shell-integration/lostty-tmux/tmux.conf` or the `*.profraw` files; `git add` only the files a task names.
- Commit messages: `lostty: …` style, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Deviations from the spec (found while planning)

- **Agent badge kind.** `ClaudeRuntime` does not record whether a pane runs Claude or Codex, and only knows "idle" for Claude (through `ClaudeUsageRuntime.sessions`). The badge is a generic agent badge: working (pulsing) and waiting (amber) for Claude and Codex, idle (steady) for Claude only.
- **Settings entry point.** ⌘, ("Preferences…") opens the Ghostty config file and `SettingsView` is not shown anywhere today. The new Settings window opens from a new app-menu item, "Lostty Settings…", placed right after "Preferences…".

## Review Focus

1. **Branch names with slashes and non-ASCII** (`feature/ünï-✨`) must list, compare and summarize exactly as named — pinned in Task 3 (`RepoReaderTests.unusualBranchNamesRoundTrip`).
2. **Repos with hundreds of branches** must not run hundreds of `rev-list` calls on open: ahead/behind is computed for at most 50 recent branches — pinned in Task 3 (`RepoReaderTests.comparesAtMostMaxComparedBranches`).
3. **Focus moving quickly between panes in different repos** must end on the last-focused repo, never a slower earlier load — pinned in Task 9 (`BranchesModelTests.laterFocusWinsOverSlowerEarlierLoad`).
4. **A repo or worktree removed while the panel is open** keeps the last snapshot with "Couldn't refresh", and a removed worktree drops out — pinned in Task 2 (`RepoParseTests.skipsBareAndPrunableWorktrees`) and Task 9 (`BranchesModelTests.keepsLastSnapshotWhenRefreshFails`).
5. **`claude` failing** (not logged in, timeout, empty output, cancelled) shows a readable message and never a stuck spinner — pinned in Task 5 (`ClaudeCLITests`, `BranchSummarizerTests`).

---

## File Structure

**Create**
- `macos/Sources/Helpers/ProcessRunner.swift` — run a program with deadline, stdin, stderr, cwd, env.
- `macos/Sources/Features/Branches/Git.swift` — `/usr/bin/git -C dir …` with timeout.
- `macos/Sources/Features/Branches/RepoSnapshot.swift` — value types: `RepoLocation`, `RepoSnapshot`, `BranchInfo`, `Upstream`, `AheadBehind`, `Worktree`, `BranchDetails`.
- `macos/Sources/Features/Branches/RepoParse.swift` — pure parsers for git output.
- `macos/Sources/Features/Branches/RepoReader.swift` — locate a pane's repo, read a snapshot, read a branch's details.
- `macos/Sources/Features/Branches/BranchSession.swift` — `BranchSession`, `AgentState`.
- `macos/Sources/Features/Branches/SessionPlacement.swift` — pure session → branch assignment.
- `macos/Sources/Features/Branches/BranchSections.swift` — pure grouping into Active / Detached / Branches / Older.
- `macos/Sources/Features/Branches/SummaryCache.swift` — on-disk summaries keyed by repo + branch.
- `macos/Sources/Features/Branches/SummaryPrompt.swift` — builds the capped prompt.
- `macos/Sources/Features/Branches/ClaudeCLI.swift` — locate `claude`, arguments, interpret results.
- `macos/Sources/Features/Branches/BranchSummarizer.swift` — `RunHandle`, git + claude run for one branch.
- `macos/Sources/Features/Branches/SessionLocator.swift` — live panes and phone-only tmux sessions; `PhonePanes` parser.
- `macos/Sources/Features/Branches/RepoWatcher.swift` — FSEvents on the git dir.
- `macos/Sources/Features/Branches/BranchesModel.swift` — per-window state machine for the panel.
- `macos/Sources/Features/Branches/BranchesPanel.swift` — the panel's SwiftUI views.
- `macos/Sources/Features/Branches/BranchesFormat.swift` — pure text helpers for rows.
- `macos/Sources/Features/Branches/BranchesActions.swift` — focus a pane / open a phone session.
- `macos/Sources/Helpers/PaneFocus.swift` — bring a pane's window front and focus it.
- `macos/Sources/Features/Extensions/SidebarPreferences.swift` — the auto-hide preference.
- `macos/Sources/Features/Extensions/SidebarAutoHide.swift` — state machine + driver.
- `macos/Sources/Features/Extensions/HoverEdge.swift` — hover-only NSView.
- `macos/Sources/Features/Settings/SettingsUI.swift` — menu item and window.
- Tests under `macos/Tests/Helpers/`, `macos/Tests/Branches/`, `macos/Tests/Extensions/`.

**Modify**
- `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift` — `.branches`, `Presentation`, `close()`, owns `BranchesModel`.
- `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift` — sidebar panel slot, auto-hide.
- `macos/Sources/Features/Extensions/ExtensionSidebarView.swift` — Branches icon, content case.
- `macos/Sources/Features/Settings/SettingsView.swift` — real settings form.
- `macos/Sources/App/macOS/AppDelegate.swift` — install the settings menu item.
- `macos/Sources/Features/MenuBar/LosttyStatusItem.swift` — use `PaneFocus`.
- `macos/Sources/Features/Sessions/SessionsUI.swift` — `openInTab`.
- `macos/Tests/Extensions/ExtensionSidebarModelTests.swift`.

---

### Task 1: ProcessRunner and Git runner

**Files:**
- Create: `macos/Sources/Helpers/ProcessRunner.swift`
- Create: `macos/Sources/Features/Branches/Git.swift`
- Test: `macos/Tests/Helpers/ProcessRunnerTests.swift`
- Test: `macos/Tests/Branches/TempRepo.swift` (test helper, no suite)
- Test: `macos/Tests/Branches/GitTests.swift`

**Interfaces:**
- Produces: `struct ProcessResult { status: Int32; stdout: String; stderr: String }`; `ProcessRunner.run(_ executable: String, _ args: [String], cwd: String? = nil, environment: [String: String] = [:], stdin: String? = nil, timeout: TimeInterval, onStart: ((Int32) -> Void)? = nil) -> ProcessResult?`; `Git.executable: String`; `Git.run(_ args: [String], in dir: String, timeout: TimeInterval = 5) -> String?`; test helper `TempRepo` (`make()`, `makeDirectory()`, `git(_:in:date:)`, `commit(_:in:date:)`).

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Helpers/ProcessRunnerTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ProcessRunnerTests {
    @Test func capturesStdoutAndStatus() throws {
        let result = try #require(ProcessRunner.run("/bin/echo", ["hello"], timeout: 5))
        #expect(result.status == 0)
        #expect(result.stdout == "hello\n")
    }

    @Test func feedsStdin() throws {
        let result = try #require(ProcessRunner.run("/bin/cat", [], stdin: "from stdin", timeout: 5))
        #expect(result.stdout == "from stdin")
    }

    @Test func capturesStderrAndFailureStatus() throws {
        let result = try #require(ProcessRunner.run("/bin/sh", ["-c", "echo oops >&2; exit 3"], timeout: 5))
        #expect(result.status == 3)
        #expect(result.stderr == "oops\n")
    }

    @Test func runsInTheGivenDirectory() throws {
        let dir = ProjectResolver.canonical(FileManager.default.temporaryDirectory.path)
        let result = try #require(ProcessRunner.run("/bin/pwd", ["-P"], cwd: dir, timeout: 5))
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == dir)
    }

    @Test func addsToTheEnvironment() throws {
        let result = try #require(ProcessRunner.run(
            "/usr/bin/env", [], environment: ["LOSTTY_TEST_VAR": "42"], timeout: 5))
        #expect(result.stdout.contains("LOSTTY_TEST_VAR=42\n"))
        #expect(result.stdout.contains("PATH="))
    }

    @Test func killsAProgramThatRunsPastTheTimeout() {
        let start = Date()
        #expect(ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.3) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func reportsThePidOnStart() {
        var pid: Int32 = 0
        _ = ProcessRunner.run("/bin/echo", [], timeout: 5, onStart: { pid = $0 })
        #expect(pid > 0)
    }

    @Test func aMissingProgramIsNil() {
        #expect(ProcessRunner.run("/nonexistent/tool", [], timeout: 5) == nil)
    }
}
#endif
```

`macos/Tests/Branches/TempRepo.swift`:

```swift
#if os(macOS)
import Foundation
@testable import Ghostty

enum TempRepoError: Error {
    case failed(String)
}

/// Throwaway git repos for tests, with a fixed identity and no user config.
struct TempRepo {
    let root: String

    /// A new empty directory under the temp dir, canonical (no /var symlink).
    static func makeDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("branches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectResolver.canonical(url.path)
    }

    /// A repo at `<new dir>/repo` on `main` with one commit, "first".
    static func make(firstCommit date: Date = Date()) throws -> TempRepo {
        let repo = TempRepo(root: try makeDirectory() + "/repo")
        try FileManager.default.createDirectory(atPath: repo.root, withIntermediateDirectories: true)
        try repo.git("init", "-q", "-b", "main")
        try repo.commit("first", date: date)
        return repo
    }

    /// Runs git in `dir` (default: the repo root); throws on failure.
    @discardableResult
    func git(_ args: String..., in dir: String? = nil, date: Date = Date()) throws -> String {
        let stamp = "\(Int(date.timeIntervalSince1970)) +0000"
        let env = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp,
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        ]
        guard let result = ProcessRunner.run(
            Git.executable, ["-C", dir ?? root] + args, environment: env, timeout: 10),
            result.status == 0
        else { throw TempRepoError.failed(args.joined(separator: " ")) }
        return result.stdout
    }

    /// Adds a file named after `message` and commits it.
    func commit(_ message: String, in dir: String? = nil, date: Date = Date()) throws {
        let directory = dir ?? root
        let file = message.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        FileManager.default.createFile(atPath: "\(directory)/\(file).txt", contents: Data(message.utf8))
        try git("add", "-A", in: directory, date: date)
        try git("commit", "-q", "-m", message, in: directory, date: date)
    }
}
#endif
```

`macos/Tests/Branches/GitTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct GitTests {
    @Test func runsGitInADirectory() throws {
        let repo = try TempRepo.make()
        let head = try #require(Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo.root))
        #expect(head == "main\n")
    }

    @Test func aFailingCommandIsNil() throws {
        let dir = try TempRepo.makeDirectory()
        #expect(Git.run(["rev-parse", "HEAD"], in: dir) == nil)
    }

    @Test func aMissingDirectoryIsNil() {
        #expect(Git.run(["status"], in: "/nonexistent/\(UUID().uuidString)") == nil)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh ProcessRunnerTests`
Expected: FAIL with `error: cannot find 'ProcessRunner' in scope`.

- [ ] **Step 3: Write the implementation**

`macos/Sources/Helpers/ProcessRunner.swift`:

```swift
#if os(macOS)
import Foundation

/// What a finished program printed and how it exited.
struct ProcessResult: Equatable, Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

/// Runs a program to completion with a deadline, the way `TmuxClient.run`
/// does: waits on semaphores (not `waitUntilExit`, which spins the run
/// loop), reads output on background queues so a full pipe can't stall it,
/// and SIGKILLs it at the deadline. Blocking: call it off the main thread.
enum ProcessRunner {
    /// nil when the program can't start or runs past `timeout`. `onStart`
    /// gets the pid, so a caller can kill a run it no longer wants.
    static func run(
        _ executable: String,
        _ args: [String],
        cwd: String? = nil,
        environment: [String: String] = [:],
        stdin: String? = nil,
        timeout: TimeInterval,
        onStart: ((Int32) -> Void)? = nil
    ) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        // stdin comes from a file, not a pipe: writing to a pipe whose reader
        // already exited would raise SIGPIPE in the app.
        var inputFile: URL?
        defer { if let inputFile { try? FileManager.default.removeItem(at: inputFile) } }
        if let stdin {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lostty-stdin-\(UUID().uuidString)")
            guard (try? Data(stdin.utf8).write(to: url)) != nil,
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            inputFile = url
            process.standardInput = handle
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        onStart?(process.processIdentifier)

        let output = Output()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output.out = out.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        read.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output.err = err.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }

        let deadline = DispatchTime.now() + timeout
        guard exited.wait(timeout: deadline) == .success else {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }
        guard read.wait(timeout: deadline) == .success else { return nil }
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: output.out, as: UTF8.self),
            stderr: String(decoding: output.err, as: UTF8.self))
    }

    /// Hands output from the reading queues back to `run`; the group orders
    /// the writes before the reads.
    private final class Output: @unchecked Sendable {
        var out = Data()
        var err = Data()
    }
}
#endif
```

`macos/Sources/Features/Branches/Git.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh ProcessRunnerTests && macos/skins-test.sh GitTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Helpers/ProcessRunner.swift macos/Sources/Features/Branches/Git.swift \
  macos/Tests/Helpers/ProcessRunnerTests.swift macos/Tests/Branches/TempRepo.swift macos/Tests/Branches/GitTests.swift
git commit -m "lostty: a process runner with a deadline, and a git runner for Branches

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Repo value types and git output parsers

**Files:**
- Create: `macos/Sources/Features/Branches/RepoSnapshot.swift`
- Create: `macos/Sources/Features/Branches/RepoParse.swift`
- Test: `macos/Tests/Branches/RepoParseTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct AheadBehind: Equatable, Sendable { var ahead: Int; var behind: Int }`
  - `enum Upstream: Equatable, Sendable { case none; case tracking(name: String, ahead: Int, behind: Int); case gone(name: String) }`
  - `struct BranchInfo: Equatable, Sendable { var name: String; var tip: String; var lastCommit: Date; var subject: String; var upstream: Upstream; var vsBase: AheadBehind? }`
  - `struct Worktree: Equatable, Sendable { var path: String; var head: String; var branch: String?; var rebasing: String?; var isMain: Bool }`
  - `struct RepoLocation: Hashable, Sendable { var root: String; var commonDir: String }`
  - `struct RepoSnapshot: Equatable, Sendable { var root: String; var commonDir: String; var base: String?; var branches: [BranchInfo]; var worktrees: [Worktree]; var name: String }`
  - `struct BranchDetails: Equatable, Sendable { var vsBase: AheadBehind?; var changedFiles: Int?; var dirtyCount: Int? }`
  - `RepoParse.branchFormat`, `RepoParse.branches(_:)`, `RepoParse.upstream(name:track:)`, `RepoParse.worktrees(_:)`, `RepoParse.shortBranch(_:)`, `RepoParse.aheadBehind(_:)`, `RepoParse.rebaseHead(_:)`, `RepoParse.lineCount(_:)`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Branches/RepoParseTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct RepoParseTests {
    @Test func parsesBranchLines() {
        let output = """
        main\taaa111\t1791839107\torigin/main\t\tfirst commit
        feat/x\tbbb222\t1791838956\torigin/feat/x\t[ahead 1, behind 2]\tsubject\twith a tab
        local\tccc333\t1791437387\t\t\tno upstream

        """
        let branches = RepoParse.branches(output)
        #expect(branches.count == 3)
        #expect(branches[0] == BranchInfo(
            name: "main", tip: "aaa111", lastCommit: Date(timeIntervalSince1970: 1791839107),
            subject: "first commit", upstream: .tracking(name: "origin/main", ahead: 0, behind: 0), vsBase: nil))
        #expect(branches[1].name == "feat/x")
        #expect(branches[1].subject == "subject\twith a tab")
        #expect(branches[1].upstream == .tracking(name: "origin/feat/x", ahead: 1, behind: 2))
        #expect(branches[2].upstream == .none)
    }

    @Test func skipsMalformedBranchLines() {
        #expect(RepoParse.branches("garbage\nmain\tsha\tnot-a-date\t\t\tx\n").isEmpty)
    }

    @Test func parsesUpstreamTracking() {
        #expect(RepoParse.upstream(name: "", track: "") == .none)
        #expect(RepoParse.upstream(name: "origin/a", track: "") == .tracking(name: "origin/a", ahead: 0, behind: 0))
        #expect(RepoParse.upstream(name: "origin/a", track: "[ahead 3]") == .tracking(name: "origin/a", ahead: 3, behind: 0))
        #expect(RepoParse.upstream(name: "origin/a", track: "[behind 4]") == .tracking(name: "origin/a", ahead: 0, behind: 4))
        #expect(RepoParse.upstream(name: "origin/a", track: "[gone]") == .gone(name: "origin/a"))
    }

    @Test func parsesWorktrees() {
        let porcelain = """
        worktree /r/main
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /r/wt
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/feature/a

        worktree /r/det
        HEAD 3333333333333333333333333333333333333333
        detached

        """
        let trees = RepoParse.worktrees(porcelain)
        #expect(trees == [
            Worktree(path: "/r/main", head: "1111111111111111111111111111111111111111", branch: "main", rebasing: nil, isMain: true),
            Worktree(path: "/r/wt", head: "2222222222222222222222222222222222222222", branch: "feature/a", rebasing: nil, isMain: false),
            Worktree(path: "/r/det", head: "3333333333333333333333333333333333333333", branch: nil, rebasing: nil, isMain: false),
        ])
    }

    @Test func skipsBareAndPrunableWorktrees() {
        let porcelain = """
        worktree /r/bare.git
        bare

        worktree /r/gone
        HEAD 4444444444444444444444444444444444444444
        branch refs/heads/old
        prunable gitdir file points to non-existent location

        worktree /r/live
        HEAD 5555555555555555555555555555555555555555
        branch refs/heads/live

        """
        let trees = RepoParse.worktrees(porcelain)
        #expect(trees.map(\.path) == ["/r/live"])
        #expect(trees[0].isMain == false)
    }

    @Test func parsesAheadBehindAsBehindThenAhead() {
        #expect(RepoParse.aheadBehind("3\t5\n") == AheadBehind(ahead: 5, behind: 3))
        #expect(RepoParse.aheadBehind("") == nil)
    }

    @Test func parsesRebaseHeadName() {
        #expect(RepoParse.rebaseHead("refs/heads/feat/x\n") == "feat/x")
        #expect(RepoParse.rebaseHead("detached HEAD\n") == nil)
    }

    @Test func countsLines() {
        #expect(RepoParse.lineCount("") == 0)
        #expect(RepoParse.lineCount("a\nb\n") == 2)
    }

    @Test func snapshotNameIsTheRootFolder() {
        let snapshot = RepoSnapshot(root: "/x/lostty", commonDir: "/x/lostty/.git", base: nil, branches: [], worktrees: [])
        #expect(snapshot.name == "lostty")
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh RepoParseTests`
Expected: FAIL with `cannot find 'RepoParse' in scope`.

- [ ] **Step 3: Write the implementation**

`macos/Sources/Features/Branches/RepoSnapshot.swift`:

```swift
#if os(macOS)
import Foundation

/// Commits a branch has that another doesn't (ahead), and the reverse (behind).
struct AheadBehind: Equatable, Sendable {
    var ahead: Int
    var behind: Int
}

/// A branch's remote-tracking branch, as `for-each-ref` reports it.
enum Upstream: Equatable, Sendable {
    case none
    case tracking(name: String, ahead: Int, behind: Int)
    /// Configured, but the remote branch was deleted.
    case gone(name: String)
}

/// A local branch.
struct BranchInfo: Equatable, Sendable {
    var name: String
    var tip: String
    var lastCommit: Date
    var subject: String
    var upstream: Upstream
    /// Against the repo's base branch; nil for the base itself and for
    /// branches not compared yet (older ones, until their row is expanded).
    var vsBase: AheadBehind?
}

/// A checkout of the repo: the main one or a linked worktree.
struct Worktree: Equatable, Sendable {
    var path: String
    var head: String
    /// nil when HEAD is detached.
    var branch: String?
    /// The branch a rebase in progress here is rewriting.
    var rebasing: String?
    var isMain: Bool
}

/// Where a repo is: every worktree of it maps to the same location.
struct RepoLocation: Hashable, Sendable {
    /// The main worktree.
    var root: String
    /// The git directory all worktrees share.
    var commonDir: String
}

/// One read of a repo, everything a closed row shows.
struct RepoSnapshot: Equatable, Sendable {
    var root: String
    var commonDir: String
    var base: String?
    var branches: [BranchInfo]
    var worktrees: [Worktree]

    var name: String { (root as NSString).lastPathComponent }
}

/// What an expanded row adds; read when the row opens.
struct BranchDetails: Equatable, Sendable {
    var vsBase: AheadBehind?
    var changedFiles: Int?
    /// Uncommitted changes where the branch is checked out.
    var dirtyCount: Int?
}
#endif
```

`macos/Sources/Features/Branches/RepoParse.swift`:

```swift
#if os(macOS)
import Foundation

/// Parsers for the git output the Branches panel reads. Pure.
enum RepoParse {
    /// `for-each-ref --format`: name, sha, committer time, upstream, track,
    /// subject — tab separated, subject last because it may contain tabs.
    static let branchFormat =
        "%(refname:short)%09%(objectname)%09%(committerdate:unix)%09%(upstream:short)%09%(upstream:track)%09%(subject)"

    static func branches(_ output: String) -> [BranchInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 6, !f[0].isEmpty, let seconds = TimeInterval(f[2]) else { return nil }
            return BranchInfo(
                name: f[0], tip: f[1], lastCommit: Date(timeIntervalSince1970: seconds),
                subject: f[5], upstream: upstream(name: f[3], track: f[4]), vsBase: nil)
        }
    }

    /// `%(upstream:track)`: "", "[gone]", "[ahead 1]", "[behind 2]", "[ahead 1, behind 2]".
    static func upstream(name: String, track: String) -> Upstream {
        guard !name.isEmpty else { return .none }
        if track == "[gone]" { return .gone(name: name) }
        var ahead = 0
        var behind = 0
        for part in track.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = count } else if words[0] == "behind" { behind = count }
        }
        return .tracking(name: name, ahead: ahead, behind: behind)
    }

    /// `worktree list --porcelain`. The first entry is the main worktree.
    /// Bare entries and prunable ones (their folder is gone) are skipped.
    static func worktrees(_ porcelain: String) -> [Worktree] {
        var result: [Worktree] = []
        for (index, block) in porcelain.components(separatedBy: "\n\n").enumerated() {
            var path: String?
            var head = ""
            var branch: String?
            var skip = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    branch = shortBranch(String(line.dropFirst("branch ".count)))
                } else if line == "bare" || line.hasPrefix("prunable") {
                    skip = true
                }
            }
            guard let path, !skip else { continue }
            result.append(Worktree(path: path, head: head, branch: branch, rebasing: nil, isMain: index == 0))
        }
        return result
    }

    static func shortBranch(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    /// `rev-list --left-right --count base...branch` prints "<behind>\t<ahead>".
    static func aheadBehind(_ output: String) -> AheadBehind? {
        let f = output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0.isNewline })
        guard f.count == 2, let behind = Int(f[0]), let ahead = Int(f[1]) else { return nil }
        return AheadBehind(ahead: ahead, behind: behind)
    }

    /// A rebase's `head-name` file: "refs/heads/feat\n" → "feat".
    static func rebaseHead(_ contents: String) -> String? {
        let ref = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ref.hasPrefix("refs/heads/") else { return nil }
        return shortBranch(ref)
    }

    static func lineCount(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline).count
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh RepoParseTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Branches/RepoSnapshot.swift macos/Sources/Features/Branches/RepoParse.swift \
  macos/Tests/Branches/RepoParseTests.swift
git commit -m "lostty: Branches reads branches, worktrees and tracking from git's output

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: RepoReader

**Files:**
- Create: `macos/Sources/Features/Branches/RepoReader.swift`
- Test: `macos/Tests/Branches/RepoReaderTests.swift`

**Interfaces:**
- Consumes: `Git.run`, `RepoParse.*`, types from Task 2, `ProjectResolver.canonical(_:)` (existing, `Features/Skins/ProjectResolver.swift`).
- Produces:
  - `RepoReader.olderAfter: TimeInterval` (30 days), `RepoReader.maxCompared: Int` (50)
  - `RepoReader.locate(pwd: String, home: String = NSHomeDirectory()) -> RepoLocation?`
  - `RepoReader.read(_ location: RepoLocation, now: Date = Date(), maxCompared: Int = RepoReader.maxCompared) -> RepoSnapshot?`
  - `RepoReader.details(for branch: BranchInfo, base: String?, worktree: Worktree?, in root: String) -> BranchDetails`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Branches/RepoReaderTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct RepoReaderTests {
    private let now = Date()
    private var sixtyDaysAgo: Date { now.addingTimeInterval(-60 * 24 * 3600) }

    /// main (2 commits, the first 60 days old), feat (+2 on main) checked out
    /// in worktree `wt`, old (at the first commit), and a detached worktree `det`.
    private func makeFixture() throws -> (repo: TempRepo, wt: String, det: String) {
        let repo = try TempRepo.make(firstCommit: sixtyDaysAgo)
        try repo.git("branch", "old")
        try repo.commit("second")
        try repo.git("checkout", "-q", "-b", "feat")
        try repo.commit("feat one")
        try repo.commit("feat two")
        try repo.git("checkout", "-q", "main")
        let parent = (repo.root as NSString).deletingLastPathComponent
        let wt = parent + "/wt"
        let det = parent + "/det"
        try repo.git("worktree", "add", "-q", wt, "feat")
        try repo.git("worktree", "add", "-q", "--detach", det, "main")
        return (repo, wt, det)
    }

    @Test func locatesTheMainWorktreeFromALinkedWorktreeSubfolder() throws {
        let (repo, wt, _) = try makeFixture()
        try FileManager.default.createDirectory(atPath: wt + "/sub", withIntermediateDirectories: true)
        let location = try #require(RepoReader.locate(pwd: wt + "/sub"))
        #expect(location.root == repo.root)
        #expect(location.commonDir == repo.root + "/.git")
        #expect(RepoReader.locate(pwd: repo.root) == location)
    }

    @Test func outsideARepoIsNil() throws {
        #expect(RepoReader.locate(pwd: try TempRepo.makeDirectory()) == nil)
    }

    @Test func aHomeDirectoryUnderGitIsNotARepo() throws {
        let repo = try TempRepo.make()
        #expect(RepoReader.locate(pwd: repo.root, home: repo.root) == nil)
    }

    @Test func readsBranchesBaseAndWorktrees() throws {
        let (repo, wt, det) = try makeFixture()
        let location = try #require(RepoReader.locate(pwd: repo.root))
        let snapshot = try #require(RepoReader.read(location, now: now))

        #expect(snapshot.base == "main")
        #expect(Set(snapshot.branches.map(\.name)) == ["main", "feat", "old"])
        let feat = try #require(snapshot.branches.first { $0.name == "feat" })
        #expect(feat.vsBase == AheadBehind(ahead: 2, behind: 0))
        #expect(feat.subject == "feat two")
        #expect(snapshot.branches.first { $0.name == "old" }?.vsBase == nil)
        #expect(snapshot.branches.first { $0.name == "main" }?.vsBase == nil)

        #expect(snapshot.worktrees.count == 3)
        #expect(snapshot.worktrees[0].isMain && snapshot.worktrees[0].branch == "main")
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == wt }?.branch == "feat")
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == det }?.branch == nil)
    }

    @Test func originHeadChoosesTheBase() throws {
        let (repo, _, _) = try makeFixture()
        try repo.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/feat")
        let snapshot = try #require(RepoReader.read(try #require(RepoReader.locate(pwd: repo.root)), now: now))
        #expect(snapshot.base == "feat")
    }

    @Test func noMainOrMasterMeansNoBase() throws {
        let repo = try TempRepo.make()
        try repo.git("branch", "-m", "trunk")
        let snapshot = try #require(RepoReader.read(try #require(RepoReader.locate(pwd: repo.root)), now: now))
        #expect(snapshot.base == nil)
        #expect(snapshot.branches.allSatisfy { $0.vsBase == nil })
    }

    @Test func readsARebaseInProgress() throws {
        let (repo, _, det) = try makeFixture()
        let gitDir = try repo.git("rev-parse", "--absolute-git-dir", in: det)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try FileManager.default.createDirectory(atPath: gitDir + "/rebase-merge", withIntermediateDirectories: true)
        try "refs/heads/feat\n".write(toFile: gitDir + "/rebase-merge/head-name", atomically: true, encoding: .utf8)
        let snapshot = try #require(RepoReader.read(try #require(RepoReader.locate(pwd: repo.root)), now: now))
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == det }?.rebasing == "feat")
    }

    @Test func comparesAtMostMaxComparedBranches() throws {
        let (repo, _, _) = try makeFixture()
        let location = try #require(RepoReader.locate(pwd: repo.root))
        let snapshot = try #require(RepoReader.read(location, now: now, maxCompared: 0))
        #expect(snapshot.branches.allSatisfy { $0.vsBase == nil })
    }

    @Test func unusualBranchNamesRoundTrip() throws {
        let (repo, _, _) = try makeFixture()
        try repo.git("branch", "feature/ünï-✨")
        let snapshot = try #require(RepoReader.read(try #require(RepoReader.locate(pwd: repo.root)), now: now))
        let branch = try #require(snapshot.branches.first { $0.name == "feature/ünï-✨" })
        #expect(branch.vsBase == AheadBehind(ahead: 0, behind: 0))
    }

    @Test func detailsCountChangedFilesAndDirtyFiles() throws {
        let (repo, wt, _) = try makeFixture()
        FileManager.default.createFile(atPath: wt + "/scratch.txt", contents: Data("x".utf8))
        let snapshot = try #require(RepoReader.read(try #require(RepoReader.locate(pwd: repo.root)), now: now))
        let feat = try #require(snapshot.branches.first { $0.name == "feat" })
        let tree = snapshot.worktrees.first { $0.branch == "feat" }
        let details = RepoReader.details(for: feat, base: "main", worktree: tree, in: snapshot.root)
        #expect(details.changedFiles == 2)
        #expect(details.dirtyCount == 1)
        #expect(details.vsBase == AheadBehind(ahead: 2, behind: 0))

        let old = try #require(snapshot.branches.first { $0.name == "old" })
        let oldDetails = RepoReader.details(for: old, base: "main", worktree: nil, in: snapshot.root)
        #expect(oldDetails.vsBase == AheadBehind(ahead: 0, behind: 1))
        #expect(oldDetails.dirtyCount == nil)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh RepoReaderTests`
Expected: FAIL with `cannot find 'RepoReader' in scope`.

- [ ] **Step 3: Write the implementation**

`macos/Sources/Features/Branches/RepoReader.swift`:

```swift
#if os(macOS)
import Foundation

/// Reads what the Branches panel shows from git. Blocking: call it off the
/// main thread.
enum RepoReader {
    /// Branches untouched this long go under "Older".
    static let olderAfter: TimeInterval = 30 * 24 * 3600
    /// At most this many branches are compared with the base per read, so a
    /// repo with hundreds of branches opens quickly.
    static let maxCompared = 50

    /// The repo `pwd` is in, from any of its worktrees. nil outside a repo,
    /// and for a home directory under git (dotfiles), as Skins does.
    static func locate(pwd: String, home: String = NSHomeDirectory()) -> RepoLocation? {
        guard let common = trimmed(Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: pwd)),
              let list = Git.run(["worktree", "list", "--porcelain"], in: pwd),
              let main = RepoParse.worktrees(list).first(where: \.isMain) else { return nil }
        let root = ProjectResolver.canonical(main.path)
        guard root.lowercased() != ProjectResolver.canonical(home).lowercased() else { return nil }
        return RepoLocation(root: root, commonDir: ProjectResolver.canonical(common))
    }

    static func read(_ location: RepoLocation, now: Date = Date(), maxCompared: Int = maxCompared) -> RepoSnapshot? {
        let root = location.root
        guard let list = Git.run(["worktree", "list", "--porcelain"], in: root),
              let refs = Git.run(["for-each-ref", "refs/heads", "--format=\(RepoParse.branchFormat)"], in: root)
        else { return nil }

        let worktrees = RepoParse.worktrees(list).map { tree -> Worktree in
            var tree = tree
            tree.rebasing = rebasingBranch(in: tree.path)
            return tree
        }
        var branches = RepoParse.branches(refs)
        let base = resolveBase(in: root, branches: Set(branches.map(\.name)))
        if let base {
            let newestFirst = branches.indices.sorted { branches[$0].lastCommit > branches[$1].lastCommit }
            var compared = 0
            for index in newestFirst where compared < maxCompared {
                let branch = branches[index]
                guard branch.name != base, now.timeIntervalSince(branch.lastCommit) <= olderAfter else { continue }
                compared += 1
                branches[index].vsBase = aheadBehind(branch.name, base: base, in: root)
            }
        }
        return RepoSnapshot(root: root, commonDir: location.commonDir, base: base, branches: branches, worktrees: worktrees)
    }

    static func details(for branch: BranchInfo, base: String?, worktree: Worktree?, in root: String) -> BranchDetails {
        var details = BranchDetails()
        if let base, base != branch.name {
            details.vsBase = branch.vsBase ?? aheadBehind(branch.name, base: base, in: root)
            details.changedFiles = Git.run(
                ["diff", "--name-only", "refs/heads/\(base)...refs/heads/\(branch.name)"], in: root
            ).map(RepoParse.lineCount)
        }
        if let worktree {
            details.dirtyCount = Git.run(["status", "--porcelain"], in: worktree.path).map(RepoParse.lineCount)
        }
        return details
    }

    private static func aheadBehind(_ branch: String, base: String, in root: String) -> AheadBehind? {
        Git.run(["rev-list", "--left-right", "--count", "refs/heads/\(base)...refs/heads/\(branch)"], in: root)
            .flatMap(RepoParse.aheadBehind)
    }

    /// `origin/HEAD`'s branch when it exists locally, else main, else master.
    private static func resolveBase(in root: String, branches: Set<String>) -> String? {
        if let remote = trimmed(Git.run(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: root)),
           let slash = remote.firstIndex(of: "/") {
            let name = String(remote[remote.index(after: slash)...])
            if branches.contains(name) { return name }
        }
        return ["main", "master"].first(where: branches.contains)
    }

    /// The branch a rebase in progress in `worktree` is rewriting.
    private static func rebasingBranch(in worktree: String) -> String? {
        guard let gitDir = trimmed(Git.run(["rev-parse", "--absolute-git-dir"], in: worktree)) else { return nil }
        for dir in ["rebase-merge", "rebase-apply"] {
            if let contents = try? String(contentsOfFile: "\(gitDir)/\(dir)/head-name", encoding: .utf8) {
                return RepoParse.rebaseHead(contents)
            }
        }
        return nil
    }

    private static func trimmed(_ output: String?) -> String? {
        guard let value = output?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh RepoReaderTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Branches/RepoReader.swift macos/Tests/Branches/RepoReaderTests.swift
git commit -m "lostty: Branches reads a repo's branches, base, worktrees and rebases

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Session placement and sections

**Files:**
- Create: `macos/Sources/Features/Branches/BranchSession.swift`
- Create: `macos/Sources/Features/Branches/SessionPlacement.swift`
- Create: `macos/Sources/Features/Branches/BranchSections.swift`
- Test: `macos/Tests/Branches/SessionPlacementTests.swift`
- Test: `macos/Tests/Branches/BranchSectionsTests.swift`

**Interfaces:**
- Consumes: `Worktree`, `RepoSnapshot`, `BranchInfo` (Task 2), `RepoReader.olderAfter` (Task 3), `ProjectResolver.canonical`.
- Produces:
  - `enum AgentState: Equatable, Sendable { case working, idle, waiting }`
  - `struct BranchSession: Identifiable, Equatable, Sendable { enum Origin: Hashable, Sendable { case pane(UUID); case phone(sessionID: String) }; var origin: Origin; var title: String; var pwd: String; var agent: AgentState?; var id: Origin; var isPhone: Bool }`
  - `struct DetachedGroup: Identifiable, Equatable, Sendable { var sha: String; var sessions: [BranchSession]; var id: String }`
  - `struct Placement: Equatable, Sendable { var byBranch: [String: [BranchSession]]; var detached: [DetachedGroup] }`
  - `SessionPlacement.assign(_ sessions: [BranchSession], worktrees: [Worktree]) -> Placement`
  - `struct BranchRow: Identifiable, Equatable, Sendable { var branch: BranchInfo; var sessions: [BranchSession]; var isBase: Bool; var isRebasing: Bool; var worktreePath: String?; var id: String }`
  - `struct BranchSections: Equatable, Sendable { var active, recent, older: [BranchRow]; var detached: [DetachedGroup]; static let empty; static func build(_ snapshot: RepoSnapshot, placement: Placement, now: Date) -> BranchSections }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Branches/SessionPlacementTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SessionPlacementTests {
    private func session(_ pwd: String, _ title: String = "pane") -> BranchSession {
        BranchSession(origin: .pane(UUID()), title: title, pwd: pwd, agent: nil)
    }

    private let trees = [
        Worktree(path: "/r/repo", head: "aaaaaaa111", branch: "main", rebasing: nil, isMain: true),
        Worktree(path: "/r/repo/.claude/worktrees/ui", head: "bbbbbbb222", branch: "ui", rebasing: nil, isMain: false),
        Worktree(path: "/r/det", head: "ccccccc333", branch: nil, rebasing: nil, isMain: false),
        Worktree(path: "/r/reb", head: "ddddddd444", branch: nil, rebasing: "feat", isMain: false),
    ]

    @Test func placesSessionsByTheirWorktreesBranch() {
        let a = session("/r/repo/src")
        let b = session("/r/repo")
        let placement = SessionPlacement.assign([a, b], worktrees: trees)
        #expect(placement.byBranch["main"] == [a, b])
    }

    @Test func aNestedWorktreeWinsOverItsParent() {
        let s = session("/r/repo/.claude/worktrees/ui/macos")
        #expect(SessionPlacement.assign([s], worktrees: trees).byBranch["ui"] == [s])
    }

    @Test func matchesPathsCaseInsensitivelyOnComponentBoundaries() {
        let upper = session("/R/Repo/src")
        let sibling = session("/r/repo-other")
        let placement = SessionPlacement.assign([upper, sibling], worktrees: trees)
        #expect(placement.byBranch["main"] == [upper])
        #expect(placement.byBranch.values.flatMap { $0 }.contains(sibling) == false)
    }

    @Test func detachedSessionsGroupByShortSha() {
        let s = session("/r/det")
        let placement = SessionPlacement.assign([s], worktrees: trees)
        #expect(placement.detached == [DetachedGroup(sha: "ccccccc", sessions: [s])])
        #expect(placement.byBranch.isEmpty)
    }

    @Test func aRebasingSessionSitsUnderTheBranchBeingRebased() {
        let s = session("/r/reb")
        #expect(SessionPlacement.assign([s], worktrees: trees).byBranch["feat"] == [s])
    }

    @Test func followsSymlinkedDirectories() throws {
        let dir = try TempRepo.makeDirectory()
        try FileManager.default.createDirectory(atPath: dir + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: dir + "/real")
        let tree = Worktree(path: dir + "/real", head: "eeeeeee", branch: "main", rebasing: nil, isMain: true)
        let s = session(dir + "/link")
        #expect(SessionPlacement.assign([s], worktrees: [tree]).byBranch["main"] == [s])
    }
}
#endif
```

`macos/Tests/Branches/BranchSectionsTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct BranchSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func branch(_ name: String, daysAgo: Double) -> BranchInfo {
        BranchInfo(name: name, tip: name + "-sha", lastCommit: now.addingTimeInterval(-daysAgo * 24 * 3600),
                   subject: "s", upstream: .none, vsBase: nil)
    }

    private func snapshot(_ branches: [BranchInfo], worktrees: [Worktree] = [], base: String? = "main") -> RepoSnapshot {
        RepoSnapshot(root: "/r", commonDir: "/r/.git", base: base, branches: branches, worktrees: worktrees)
    }

    @Test func activeFirstThenRecentThenOlder() {
        let s = BranchSession(origin: .pane(UUID()), title: "p", pwd: "/r", agent: .working)
        let snap = snapshot([branch("main", daysAgo: 1), branch("feat", daysAgo: 2), branch("stale", daysAgo: 45),
                             branch("new", daysAgo: 0.5)])
        let sections = BranchSections.build(snap, placement: Placement(byBranch: ["feat": [s]], detached: []), now: now)
        #expect(sections.active.map(\.id) == ["feat"])
        #expect(sections.active[0].sessions == [s])
        #expect(sections.recent.map(\.id) == ["new", "main"])
        #expect(sections.older.map(\.id) == ["stale"])
    }

    @Test func theBaseIsNeverOlder() {
        let sections = BranchSections.build(snapshot([branch("main", daysAgo: 90)]), placement: Placement(), now: now)
        #expect(sections.recent.map(\.id) == ["main"])
        #expect(sections.recent[0].isBase)
    }

    @Test func thirtyDaysIsStillRecent() {
        let sections = BranchSections.build(
            snapshot([branch("edge", daysAgo: 30), branch("past", daysAgo: 30.01)], base: nil),
            placement: Placement(), now: now)
        #expect(sections.recent.map(\.id) == ["edge"])
        #expect(sections.older.map(\.id) == ["past"])
    }

    @Test func marksRebasingAndLinkedWorktrees() {
        let trees = [
            Worktree(path: "/r", head: "1", branch: "main", rebasing: nil, isMain: true),
            Worktree(path: "/wt/feat", head: "2", branch: "feat", rebasing: nil, isMain: false),
            Worktree(path: "/wt/reb", head: "3", branch: nil, rebasing: "fix", isMain: false),
        ]
        let sections = BranchSections.build(
            snapshot([branch("main", daysAgo: 1), branch("feat", daysAgo: 1), branch("fix", daysAgo: 1)], worktrees: trees),
            placement: Placement(), now: now)
        let rows = Dictionary(uniqueKeysWithValues: sections.recent.map { ($0.id, $0) })
        #expect(rows["main"]?.worktreePath == nil)
        #expect(rows["feat"]?.worktreePath == "/wt/feat")
        #expect(rows["fix"]?.isRebasing == true)
    }

    @Test func carriesDetachedGroups() {
        let group = DetachedGroup(sha: "abc1234", sessions: [])
        let sections = BranchSections.build(snapshot([]), placement: Placement(byBranch: [:], detached: [group]), now: now)
        #expect(sections.detached == [group])
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh SessionPlacementTests`
Expected: FAIL with `cannot find 'BranchSession' in scope`.

- [ ] **Step 3: Write the implementation**

`macos/Sources/Features/Branches/BranchSession.swift`:

```swift
#if os(macOS)
import Foundation

/// What an agent in a pane is doing, as Lostty's Claude wiring knows it.
/// Lostty can't tell Claude from Codex, and only knows "idle" for Claude.
enum AgentState: Equatable, Sendable {
    case working
    case idle
    /// Finished or asking while you were looking elsewhere.
    case waiting
}

/// A Lostty session: a pane on the Mac, or a tmux session only the phone shows.
struct BranchSession: Identifiable, Equatable, Sendable {
    enum Origin: Hashable, Sendable {
        case pane(UUID)
        case phone(sessionID: String)
    }

    var origin: Origin
    var title: String
    var pwd: String
    var agent: AgentState?

    var id: Origin { origin }
    var isPhone: Bool {
        if case .phone = origin { return true }
        return false
    }
}
#endif
```

`macos/Sources/Features/Branches/SessionPlacement.swift`:

```swift
#if os(macOS)
import Foundation

/// Sessions on a detached HEAD at the same commit.
struct DetachedGroup: Identifiable, Equatable, Sendable {
    var sha: String
    var sessions: [BranchSession]
    var id: String { sha }
}

/// Which sessions are on which branch.
struct Placement: Equatable, Sendable {
    var byBranch: [String: [BranchSession]] = [:]
    var detached: [DetachedGroup] = []
}

enum SessionPlacement {
    /// Puts each session under the branch of the worktree its directory is
    /// in (the deepest one, so nested worktrees win), the branch a rebase
    /// there is rewriting, or a detached group. Sessions outside every
    /// worktree are left out. Paths compare canonically and case-insensitively.
    static func assign(_ sessions: [BranchSession], worktrees: [Worktree]) -> Placement {
        let keyed = worktrees.map { (tree: $0, key: ProjectResolver.canonical($0.path).lowercased()) }
        var placement = Placement()
        var detached: [String: [BranchSession]] = [:]
        var detachedOrder: [String] = []
        for session in sessions {
            let dir = ProjectResolver.canonical(session.pwd).lowercased()
            guard let tree = keyed
                .filter({ dir == $0.key || dir.hasPrefix($0.key + "/") })
                .max(by: { $0.key.count < $1.key.count })?.tree else { continue }
            if let branch = tree.branch ?? tree.rebasing {
                placement.byBranch[branch, default: []].append(session)
            } else {
                let sha = String(tree.head.prefix(7))
                if detached[sha] == nil { detachedOrder.append(sha) }
                detached[sha, default: []].append(session)
            }
        }
        placement.detached = detachedOrder.map { DetachedGroup(sha: $0, sessions: detached[$0] ?? []) }
        return placement
    }
}
#endif
```

`macos/Sources/Features/Branches/BranchSections.swift`:

```swift
#if os(macOS)
import Foundation

/// One branch as the panel lists it.
struct BranchRow: Identifiable, Equatable, Sendable {
    var branch: BranchInfo
    var sessions: [BranchSession]
    var isBase: Bool
    var isRebasing: Bool
    /// Where the branch is checked out, when that's a linked worktree.
    var worktreePath: String?

    var id: String { branch.name }
}

/// The panel's groups, in display order.
struct BranchSections: Equatable, Sendable {
    /// Branches with sessions on them.
    var active: [BranchRow] = []
    var detached: [DetachedGroup] = []
    /// Other branches touched within `RepoReader.olderAfter`, and the base.
    var recent: [BranchRow] = []
    /// Shown collapsed.
    var older: [BranchRow] = []

    static let empty = BranchSections()

    /// Each group is newest commit first.
    static func build(_ snapshot: RepoSnapshot, placement: Placement, now: Date) -> BranchSections {
        let rebasing = Set(snapshot.worktrees.compactMap(\.rebasing))
        var linked: [String: String] = [:]
        for tree in snapshot.worktrees where !tree.isMain {
            if let branch = tree.branch, linked[branch] == nil { linked[branch] = tree.path }
        }
        let rows = snapshot.branches
            .sorted { $0.lastCommit != $1.lastCommit ? $0.lastCommit > $1.lastCommit : $0.name < $1.name }
            .map { branch in
                BranchRow(
                    branch: branch, sessions: placement.byBranch[branch.name] ?? [],
                    isBase: branch.name == snapshot.base, isRebasing: rebasing.contains(branch.name),
                    worktreePath: linked[branch.name])
            }

        var sections = BranchSections(detached: placement.detached)
        for row in rows {
            if !row.sessions.isEmpty {
                sections.active.append(row)
            } else if row.isBase || now.timeIntervalSince(row.branch.lastCommit) <= RepoReader.olderAfter {
                sections.recent.append(row)
            } else {
                sections.older.append(row)
            }
        }
        return sections
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh SessionPlacementTests && macos/skins-test.sh BranchSectionsTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Branches/BranchSession.swift macos/Sources/Features/Branches/SessionPlacement.swift \
  macos/Sources/Features/Branches/BranchSections.swift \
  macos/Tests/Branches/SessionPlacementTests.swift macos/Tests/Branches/BranchSectionsTests.swift
git commit -m "lostty: Branches places sessions on branches and groups the list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Branch summaries (cache, prompt, claude CLI, summarizer)

**Files:**
- Create: `macos/Sources/Features/Branches/SummaryCache.swift`
- Create: `macos/Sources/Features/Branches/SummaryPrompt.swift`
- Create: `macos/Sources/Features/Branches/ClaudeCLI.swift`
- Create: `macos/Sources/Features/Branches/BranchSummarizer.swift`
- Test: `macos/Tests/Branches/SummaryCacheTests.swift`
- Test: `macos/Tests/Branches/SummaryPromptTests.swift`
- Test: `macos/Tests/Branches/ClaudeCLITests.swift`
- Test: `macos/Tests/Branches/BranchSummarizerTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner`, `ProcessResult` (Task 1), `Git.run` (Task 1), `TempRepo` (tests).
- Produces:
  - `struct BranchSummary: Codable, Equatable, Sendable { var tip: String; var text: String; var createdAt: Date; func isOutdated(tip: String) -> Bool }`
  - `@MainActor final class SummaryCache { static let shared; static var defaultURL: URL; init(url: URL); func summary(repo: String, branch: String) -> BranchSummary?; func store(_: BranchSummary, repo: String, branch: String) }`
  - `SummaryPrompt.limit` (60_000), `SummaryPrompt.build(branch:base:log:diff:stat:) -> String`
  - `enum SummaryError: Error, Equatable, Sendable { case timedOut, cancelled, git, failed(String); var message: String }`
  - `ClaudeCLI.timeout`, `ClaudeCLI.arguments: [String]`, `ClaudeCLI.parseLocate(_:) -> String?`, `ClaudeCLI.locate(shell:) -> String?`, `ClaudeCLI.interpret(_ result: ProcessResult?, cancelled: Bool) -> Result<String, SummaryError>`
  - `final class RunHandle: @unchecked Sendable { func started(_ pid: Int32); func cancel(); var isCancelled: Bool }`
  - `BranchSummarizer.run(branch: String, base: String, root: String, claude: String, handle: RunHandle) -> Result<String, SummaryError>`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Branches/SummaryCacheTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SummaryCacheTests {
    private func url() throws -> URL {
        URL(fileURLWithPath: try TempRepo.makeDirectory()).appendingPathComponent("nested/summaries.json")
    }

    @Test func storesAndReloadsByRepoAndBranch() throws {
        let file = try url()
        let summary = BranchSummary(tip: "abc", text: "Adds X.", createdAt: Date(timeIntervalSince1970: 100))
        SummaryCache(url: file).store(summary, repo: "/r/.git", branch: "feat")
        let reloaded = SummaryCache(url: file)
        #expect(reloaded.summary(repo: "/r/.git", branch: "feat") == summary)
        #expect(reloaded.summary(repo: "/r/.git", branch: "main") == nil)
        #expect(reloaded.summary(repo: "/other/.git", branch: "feat") == nil)
    }

    @Test func aSummaryIsOutdatedOnceTheTipMoves() {
        let summary = BranchSummary(tip: "abc", text: "t", createdAt: Date())
        #expect(summary.isOutdated(tip: "abc") == false)
        #expect(summary.isOutdated(tip: "def"))
    }

    @Test func aCorruptFileReadsAsEmptyAndIsRewritten() throws {
        let file = try url()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let cache = SummaryCache(url: file)
        #expect(cache.summary(repo: "/r/.git", branch: "feat") == nil)
        cache.store(BranchSummary(tip: "1", text: "t", createdAt: Date()), repo: "/r/.git", branch: "feat")
        #expect(SummaryCache(url: file).summary(repo: "/r/.git", branch: "feat")?.tip == "1")
    }
}
#endif
```

`macos/Tests/Branches/SummaryPromptTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SummaryPromptTests {
    @Test func aSmallBranchSendsTheWholeDiff() {
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: "Add X\n", diff: "+x\n", stat: "x | 1 +")
        #expect(prompt.contains("\"feat\""))
        #expect(prompt.contains("\"main\""))
        #expect(prompt.contains("Add X"))
        #expect(prompt.contains("Diff:\n+x\n"))
        #expect(!prompt.contains("truncated"))
    }

    @Test func aLargeDiffIsCappedWithTheStatFirst() {
        let diff = String(repeating: "+ some changed line ✨\n", count: 10_000)
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: "Add X\n", diff: diff, stat: "a.swift | 900 +")
        #expect(prompt.utf8.count <= SummaryPrompt.limit + 32)
        #expect(prompt.contains("Files changed:\na.swift | 900 +"))
        #expect(prompt.hasSuffix("[diff truncated]"))
    }

    @Test func aHugeLogIsCappedToo() {
        let log = String(repeating: "commit subject\n", count: 20_000)
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: log, diff: "+x\n", stat: "x | 1 +")
        #expect(prompt.utf8.count <= SummaryPrompt.limit + 32)
    }
}
#endif
```

`macos/Tests/Branches/ClaudeCLITests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ClaudeCLITests {
    @Test func locateTakesTheLastAbsolutePath() {
        #expect(ClaudeCLI.parseLocate("welcome to zsh\n/Users/me/.local/bin/claude\n") == "/Users/me/.local/bin/claude")
        #expect(ClaudeCLI.parseLocate("claude: aliased to foo\n") == nil)
        #expect(ClaudeCLI.parseLocate("") == nil)
    }

    @Test func runsHeadlessWithNoToolsOnHaiku() {
        let args = ClaudeCLI.arguments
        #expect(args.first == "-p")
        #expect(args.contains("--no-session-persistence"))
        #expect(args.firstIndex(of: "--model").map { args[$0 + 1] } == "haiku")
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "")
    }

    @Test func successIsTheTrimmedText() {
        let result = ProcessResult(status: 0, stdout: "  Adds X.\n", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .success("Adds X."))
    }

    @Test func failureShowsTheFirstErrorLine() {
        let result = ProcessResult(status: 1, stdout: "", stderr: "\nInvalid API key · Please run /login\nmore\n")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Invalid API key · Please run /login")))
    }

    @Test func failureWithNoOutputNamesTheStatus() {
        let result = ProcessResult(status: 2, stdout: "", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude exited with status 2")))
    }

    @Test func emptyOutputIsAFailure() {
        let result = ProcessResult(status: 0, stdout: "\n", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude returned nothing")))
    }

    @Test func noResultIsATimeoutAndCancelWins() {
        #expect(ClaudeCLI.interpret(nil, cancelled: false) == .failure(.timedOut))
        #expect(ClaudeCLI.interpret(ProcessResult(status: 9, stdout: "", stderr: ""), cancelled: true) == .failure(.cancelled))
    }

    @Test func errorsHaveReadableMessages() {
        #expect(SummaryError.timedOut.message == "Claude took longer than a minute.")
        #expect(SummaryError.git.message == "Couldn't read this branch's changes.")
        #expect(SummaryError.failed("x").message == "x")
    }
}
#endif
```

`macos/Tests/Branches/BranchSummarizerTests.swift` (uses a fake `claude` script; never the real one):

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct BranchSummarizerTests {
    /// An executable stand-in for `claude` that runs `body` after reading stdin.
    private func fakeClaude(_ body: String) throws -> String {
        let path = try TempRepo.makeDirectory() + "/claude"
        try "#!/bin/sh\ncat > /dev/null\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func branchRepo() throws -> TempRepo {
        let repo = try TempRepo.make()
        try repo.git("checkout", "-q", "-b", "feat")
        try repo.commit("feat one")
        return repo
    }

    @Test func returnsWhatClaudePrints() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo 'Adds feat one.'")
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .success("Adds feat one."))
    }

    @Test func reportsClaudesError() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo 'Not logged in' >&2; exit 1")
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .failure(.failed("Not logged in")))
    }

    @Test func aMissingBranchIsAGitError() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo never")
        let result = BranchSummarizer.run(branch: "nope", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .failure(.git))
    }

    @Test func cancelKillsTheRun() throws {
        let repo = try branchRepo()
        // exec: the pid Cancel kills is sleep itself, so nothing keeps the pipes open.
        let claude = try fakeClaude("exec sleep 10")
        let handle = RunHandle()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { handle.cancel() }
        let start = Date()
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: handle)
        #expect(result == .failure(.cancelled))
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh SummaryCacheTests`
Expected: FAIL with `cannot find 'SummaryCache' in scope`.

- [ ] **Step 3: Write the implementation**

`macos/Sources/Features/Branches/SummaryCache.swift`:

```swift
#if os(macOS)
import Foundation

/// A branch summary from Claude, for the branch tip it described.
struct BranchSummary: Codable, Equatable, Sendable {
    var tip: String
    var text: String
    var createdAt: Date

    /// The branch moved since: the summary may no longer describe it.
    func isOutdated(tip current: String) -> Bool { tip != current }
}

/// Summaries kept across launches, so a branch is only summarized again
/// when someone asks.
@MainActor
final class SummaryCache {
    static let shared = SummaryCache(url: defaultURL)

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/branch-summaries.json")
    }

    private let url: URL
    private var entries: [String: BranchSummary]

    /// An unreadable file reads as empty; the next store rewrites it.
    init(url: URL) {
        self.url = url
        entries = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: BranchSummary].self, from: $0) } ?? [:]
    }

    /// `repo` is the repo's common git dir, the same for all its worktrees.
    func summary(repo: String, branch: String) -> BranchSummary? {
        entries[Self.key(repo, branch)]
    }

    func store(_ summary: BranchSummary, repo: String, branch: String) {
        entries[Self.key(repo, branch)] = summary
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func key(_ repo: String, _ branch: String) -> String { repo + "\n" + branch }
}
#endif
```

`macos/Sources/Features/Branches/SummaryPrompt.swift`:

```swift
#if os(macOS)
import Foundation

/// The prompt for one branch summary, capped at `limit` bytes.
enum SummaryPrompt {
    static let limit = 60_000

    /// Commits plus the whole diff when it fits; otherwise the file list
    /// (`diff --stat`) and as much of the diff as fits.
    static func build(branch: String, base: String, log: String, diff: String, stat: String) -> String {
        let commits = truncate(log, toBytes: limit / 4)
        let header = """
        Summarize what the git branch "\(branch)" changes compared with "\(base)", for a developer deciding \
        what the branch is about. Answer in 2 to 4 plain sentences: what it changes, and why if the commits say. \
        No headings, lists or preamble.

        Commits:
        \(commits.isEmpty ? "(none)" : commits)

        """
        let full = header + "Diff:\n" + diff
        if full.utf8.count <= limit { return full }

        let marker = "\n[diff truncated]"
        let capped = header + "Files changed:\n" + truncate(stat, toBytes: limit / 4) + "\nDiff (truncated):\n"
        let room = max(0, limit - capped.utf8.count - marker.utf8.count)
        return capped + truncate(diff, toBytes: room) + marker
    }

    /// The longest prefix of `text` within `bytes` UTF-8 bytes, whole characters only.
    static func truncate(_ text: String, toBytes bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let size = text[index].utf8.count
            if used + size > bytes { break }
            used += size
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}
#endif
```

`macos/Sources/Features/Branches/ClaudeCLI.swift`:

```swift
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

    /// Where `claude` is, looked up through the user's login shell (Lostty
    /// started from the Dock has a bare PATH). Blocking, up to 5 s.
    static func locate(shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") -> String? {
        guard let result = ProcessRunner.run(shell, ["-lic", "command -v claude"], timeout: 5),
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
```

`macos/Sources/Features/Branches/BranchSummarizer.swift`:

```swift
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
    static func run(branch: String, base: String, root: String, claude: String, handle: RunHandle) -> Result<String, SummaryError> {
        let commits = "refs/heads/\(base)..refs/heads/\(branch)"
        let changes = "refs/heads/\(base)...refs/heads/\(branch)"
        guard let log = Git.run(["log", "--format=%s%n%b", commits], in: root),
              let diff = Git.run(["diff", changes], in: root, timeout: 15),
              let stat = Git.run(["diff", "--stat", changes], in: root)
        else { return .failure(.git) }
        guard !handle.isCancelled else { return .failure(.cancelled) }

        let prompt = SummaryPrompt.build(branch: branch, base: base, log: log, diff: diff, stat: stat)
        // claude may be a script that needs its own folder (node) on PATH.
        let folder = (claude as NSString).deletingLastPathComponent
        let result = ProcessRunner.run(
            claude, ClaudeCLI.arguments,
            cwd: NSTemporaryDirectory(),
            environment: ["PATH": "\(folder):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
            stdin: prompt, timeout: ClaudeCLI.timeout, onStart: handle.started)
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh SummaryCacheTests && macos/skins-test.sh SummaryPromptTests && macos/skins-test.sh ClaudeCLITests && macos/skins-test.sh BranchSummarizerTests`
Expected: `** TEST SUCCEEDED **` for all four.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Branches/SummaryCache.swift macos/Sources/Features/Branches/SummaryPrompt.swift \
  macos/Sources/Features/Branches/ClaudeCLI.swift macos/Sources/Features/Branches/BranchSummarizer.swift \
  macos/Tests/Branches/SummaryCacheTests.swift macos/Tests/Branches/SummaryPromptTests.swift \
  macos/Tests/Branches/ClaudeCLITests.swift macos/Tests/Branches/BranchSummarizerTests.swift
git commit -m "lostty: summarize a branch with claude -p, cached by its tip

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Sidebar apps declare a presentation; Branches gets its icon and panel slot

**Files:**
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarView.swift`
- Create: `macos/Sources/Features/Branches/BranchesPanel.swift` (shell: header + back; filled in Task 10)
- Test: `macos/Tests/Extensions/ExtensionSidebarModelTests.swift`

**Interfaces:**
- Produces: `LosttyExtension.branches`; `LosttyExtension.Presentation { case overlay; case sidebar(width: CGFloat) }`; `LosttyExtension.presentation`; `ExtensionSidebarModel.close()`; `BranchesPanel(onClose:)` (Task 10 changes it to `BranchesPanel(model:onClose:)`).

- [ ] **Step 1: Update the tests (failing)**

Replace the body of `macos/Tests/Extensions/ExtensionSidebarModelTests.swift` with:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    @Test func startsWithNothingOpen() {
        let model = ExtensionSidebarModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() {
        let model = ExtensionSidebarModel()
        model.select(.skins)
        #expect(model.active == .skins)
        model.select(.skins)
        #expect(model.active == nil)
    }

    @Test func clickingAnotherIconSwitchesToIt() {
        let model = ExtensionSidebarModel()
        model.select(.branches)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func closeLeavesAnyOpenApp() {
        let model = ExtensionSidebarModel()
        model.select(.branches)
        model.close()
        #expect(model.active == nil)
    }

    @Test func sidebarOrderIsBranchesThenSkins() {
        #expect(LosttyExtension.allCases == [.branches, .skins])
        #expect(LosttyExtension.branches.title == "Branches")
        #expect(LosttyExtension.skins.title == "Skins")
    }

    @Test func branchesOpensInTheSidebarAndSkinsOverTheTerminal() {
        #expect(LosttyExtension.branches.presentation == .sidebar(width: 340))
        #expect(LosttyExtension.skins.presentation == .overlay)
    }

    @Test func tracksTheFocusedPane() {
        let model = ExtensionSidebarModel()
        let pane = UUID()
        model.focusedSurfaceID = pane
        #expect(model.focusedSurfaceID == pane)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh ExtensionSidebarModelTests`
Expected: FAIL with `type 'LosttyExtension' has no member 'branches'`.

- [ ] **Step 3: Implement the model change**

In `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`, replace the `LosttyExtension` enum with:

```swift
/// An extension reachable from the window's sidebar. Order is sidebar order.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case branches
    case skins

    /// How an open extension shows: over the terminal, or inside the
    /// sidebar, which widens to `width` over the terminal's edge.
    enum Presentation: Equatable {
        case overlay
        case sidebar(width: CGFloat)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .branches: "Branches"
        case .skins: "Skins"
        }
    }

    var presentation: Presentation {
        switch self {
        case .branches: .sidebar(width: 340)
        case .skins: .overlay
        }
    }
}
```

and add to `ExtensionSidebarModel`, after `select(_:)`:

```swift
    /// A panel's back button and Esc.
    func close() {
        active = nil
    }
```

- [ ] **Step 4: Create the panel shell**

`macos/Sources/Features/Branches/BranchesPanel.swift`:

```swift
#if os(macOS)
import SwiftUI

/// The Branches app, inside the widened sidebar.
struct BranchesPanel: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BranchesHeader(title: "Branches", subtitle: nil, busy: false, onClose: onClose)
            Divider().overlay(LosttyTheme.hairline)
            Spacer(minLength: 0)
        }
        .modifier(PanelEscape(onClose: onClose))
    }
}

/// "‹ Apps" on the left, the repo on the right.
struct BranchesHeader: View {
    let title: String
    let subtitle: String?
    let busy: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Apps").font(.system(size: 12))
                }
                .foregroundStyle(LosttyTheme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to apps")
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Esc closes the panel, but only once the panel has focus (a click inside
/// it): Esc typed in the terminal stays with the terminal.
struct PanelEscape: ViewModifier {
    let onClose: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onTapGesture { focused = true }
            .onExitCommand(perform: onClose)
    }
}
#endif
```

- [ ] **Step 5: Add the icon and content case**

In `macos/Sources/Features/Extensions/ExtensionSidebarView.swift`:

1. In `ExtensionIcon.body`'s `switch ext`, add before `case .skins:`:

```swift
        case .branches:
            BranchesIcon()
```

2. Add after the `ExtensionIcon` struct:

```swift
/// A git-branch mark on deep green.
private struct BranchesIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.56, blue: 0.38), Color(red: 0.03, green: 0.22, blue: 0.15)],
                startPoint: .top, endPoint: .bottom)
            BranchGlyph()
                .frame(width: 24, height: 24)
                .shadow(color: Color(red: 0.55, green: 1, blue: 0.75).opacity(0.6), radius: 3)
        }
        .frame(width: 44, height: 44)
        .modifier(IOSIconChrome())
    }
}

/// A trunk with a branch forking off it, three commit dots.
private struct BranchGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let line = Color(red: 0.86, green: 1, blue: 0.92)
            var trunk = Path()
            trunk.move(to: p(7, 4))
            trunk.addLine(to: p(7, 20))
            var fork = Path()
            fork.move(to: p(17, 6.5))
            fork.addCurve(to: p(7, 16), control1: p(17, 12), control2: p(9, 11))
            ctx.stroke(trunk, with: .color(line), lineWidth: 2 * s)
            ctx.stroke(fork, with: .color(line), lineWidth: 2 * s)
            for center in [p(7, 4), p(7, 20), p(17, 6.5)] {
                let r = 2.6 * s
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white))
            }
        }
    }
}
```

3. In `ExtensionContentView.body`'s `switch ext`, add before `case .skins:`:

```swift
        case .branches:
            BranchesPanel(onClose: model.close)
```

- [ ] **Step 6: Give sidebar apps their slot in the layout**

Replace `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift`'s struct with:

```swift
/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, and the Claude usage bar below
/// both. An open overlay extension covers the terminal content; an open
/// sidebar extension grows out of the strip over the terminal's edge. The
/// terminal never changes size.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                content()
                    .overlay {
                        if let ext = model.active, ext.presentation == .overlay {
                            ExtensionContentView(ext: ext, model: model)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topTrailing) { NotificationStackView() }
                    .overlay(alignment: .trailing) { sidebarPanel }
                ExtensionSidebarView(model: model)
            }
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }

    /// The open sidebar extension, flush against the strip.
    @ViewBuilder private var sidebarPanel: some View {
        if let ext = model.active, case .sidebar(let width) = ext.presentation {
            ExtensionContentView(ext: ext, model: model)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                .shadow(color: .black.opacity(0.35), radius: 12, x: -4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `macos/skins-test.sh ExtensionSidebarModelTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Extensions/ExtensionSidebarModel.swift \
  macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift \
  macos/Sources/Features/Extensions/ExtensionSidebarView.swift \
  macos/Sources/Features/Branches/BranchesPanel.swift macos/Tests/Extensions/ExtensionSidebarModelTests.swift
git commit -m "lostty: sidebar apps can open inside the sidebar; Branches is the first

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Sidebar auto-hide

**Files:**
- Create: `macos/Sources/Features/Extensions/SidebarPreferences.swift`
- Create: `macos/Sources/Features/Extensions/SidebarAutoHide.swift`
- Create: `macos/Sources/Features/Extensions/HoverEdge.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift`
- Test: `macos/Tests/Extensions/SidebarAutoHideTests.swift`
- Test: `macos/Tests/Extensions/SidebarPreferencesTests.swift`

**Interfaces:**
- Consumes: `ExtensionSidebarLayout.sidebarPanel` (Task 6), `ExtensionSidebarView.width`.
- Produces: `@MainActor final class SidebarPreferences: ObservableObject { static let shared; static let autoHideKey = "LosttySidebarAutoHide"; init(defaults: UserDefaults = .ghostty); @Published var autoHide: Bool }`; `struct SidebarAutoHide`; `@MainActor final class SidebarAutoHideDriver: ObservableObject`; `struct HoverEdge: NSViewRepresentable`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Extensions/SidebarAutoHideTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SidebarAutoHideTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test func startsHidden() {
        #expect(SidebarAutoHide().isVisible == false)
    }

    @Test func theEdgeRevealsIt() {
        var machine = SidebarAutoHide()
        machine.pointer(.edge, inside: true, now: t0)
        #expect(machine.isVisible)
    }

    @Test func leavingHidesAfterTheDelay() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(0.4))
        #expect(machine.isVisible)
        machine.tick(now: t0.addingTimeInterval(0.5))
        #expect(machine.isVisible == false)
    }

    @Test func movingFromTheEdgeIntoTheSidebarKeepsItShown() {
        var machine = SidebarAutoHide()
        machine.pointer(.edge, inside: true, now: t0)
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.edge, inside: false, now: t0)
        #expect(machine.hideDeadline == nil)
        machine.tick(now: t0.addingTimeInterval(5))
        #expect(machine.isVisible)
    }

    @Test func comingBackCancelsTheHide() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.pointer(.sidebar, inside: true, now: t0.addingTimeInterval(0.2))
        machine.tick(now: t0.addingTimeInterval(1))
        #expect(machine.isVisible)
    }

    @Test func neverHidesWhileAnAppIsOpen() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.appChanged(open: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(60))
        #expect(machine.isVisible)
    }

    @Test func closingAnAppWithThePointerAwayStartsTheHide() {
        var machine = SidebarAutoHide()
        machine.appChanged(open: true, now: t0)
        machine.appChanged(open: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(0.5))
        #expect(machine.isVisible == false)
    }

    @Test func closingAnAppWithThePointerOnTheSidebarKeepsIt() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.appChanged(open: true, now: t0)
        machine.appChanged(open: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(5))
        #expect(machine.isVisible)
    }

    @MainActor
    @Test func theDriverHidesWhenItsTimerFires() {
        var clock = t0
        var pending: [@MainActor () -> Void] = []
        let driver = SidebarAutoHideDriver(now: { clock }, schedule: { _, work in pending.append(work) })
        driver.pointer(.edge, inside: true)
        driver.pointer(.edge, inside: false)
        #expect(driver.isVisible)
        clock = t0.addingTimeInterval(0.5)
        pending.forEach { $0() }
        #expect(driver.isVisible == false)
    }
}
#endif
```

`macos/Tests/Extensions/SidebarPreferencesTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SidebarPreferencesTests {
    @Test func autoHideIsOffByDefaultAndRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "SidebarPreferencesTests-\(UUID().uuidString)"))
        let preferences = SidebarPreferences(defaults: defaults)
        #expect(preferences.autoHide == false)
        preferences.autoHide = true
        #expect(defaults.bool(forKey: SidebarPreferences.autoHideKey))
        #expect(SidebarPreferences(defaults: defaults).autoHide)
        #expect(SidebarPreferences.autoHideKey == "LosttySidebarAutoHide")
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh SidebarAutoHideTests`
Expected: FAIL with `cannot find 'SidebarAutoHide' in scope`.

- [ ] **Step 3: Write the preference, state machine, driver and hover edge**

`macos/Sources/Features/Extensions/SidebarPreferences.swift`:

```swift
#if os(macOS)
import Foundation

/// Lostty Settings → Sidebar. Every window observes it, so a change applies
/// everywhere at once.
@MainActor
final class SidebarPreferences: ObservableObject {
    static let shared = SidebarPreferences()
    static let autoHideKey = "LosttySidebarAutoHide"

    private let defaults: UserDefaults

    /// Hide the icon strip until the pointer reaches the window's right
    /// edge. It never hides while an app is open.
    @Published var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Self.autoHideKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        autoHide = defaults.bool(forKey: Self.autoHideKey)
    }
}
#endif
```

`macos/Sources/Features/Extensions/SidebarAutoHide.swift`:

```swift
#if os(macOS)
import Foundation

/// When an auto-hiding sidebar shows. Shown while the pointer is on the
/// window's right edge or on the sidebar, or while an app is open; hidden
/// `hideDelay` after none of those holds.
struct SidebarAutoHide: Equatable {
    static let hideDelay: TimeInterval = 0.5

    enum Region: Hashable {
        /// The thin reveal strip at the window's right edge.
        case edge
        /// The sidebar itself, with any open panel.
        case sidebar
    }

    enum State: Equatable {
        case hidden
        case shown
        case hiding(deadline: Date)
    }

    private(set) var state: State = .hidden
    private var appOpen = false
    private var inside: Set<Region> = []

    var isVisible: Bool { state != .hidden }

    var hideDeadline: Date? {
        if case .hiding(let deadline) = state { return deadline }
        return nil
    }

    mutating func pointer(_ region: Region, inside isInside: Bool, now: Date) {
        if isInside {
            inside.insert(region)
            state = .shown
        } else {
            inside.remove(region)
            startHidingIfIdle(now: now)
        }
    }

    mutating func appChanged(open: Bool, now: Date) {
        appOpen = open
        if open {
            state = .shown
        } else {
            startHidingIfIdle(now: now)
        }
    }

    mutating func tick(now: Date) {
        if let deadline = hideDeadline, now >= deadline { state = .hidden }
    }

    private mutating func startHidingIfIdle(now: Date) {
        guard inside.isEmpty, !appOpen, isVisible else { return }
        state = .hiding(deadline: now.addingTimeInterval(Self.hideDelay))
    }
}

/// Runs a window's `SidebarAutoHide` against the clock.
@MainActor
final class SidebarAutoHideDriver: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    @Published private(set) var machine = SidebarAutoHide()

    private let now: () -> Date
    private let schedule: Scheduler

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        }
    ) {
        self.now = now
        self.schedule = schedule
    }

    var isVisible: Bool { machine.isVisible }

    func pointer(_ region: SidebarAutoHide.Region, inside: Bool) {
        machine.pointer(region, inside: inside, now: now())
        armHide()
    }

    func appChanged(open: Bool) {
        machine.appChanged(open: open, now: now())
        armHide()
    }

    /// Auto-hide was just turned on or off.
    func reset(appOpen: Bool) {
        machine = SidebarAutoHide()
        if appOpen { machine.appChanged(open: true, now: now()) }
    }

    private func armHide() {
        guard let deadline = machine.hideDeadline else { return }
        schedule(max(0, deadline.timeIntervalSince(now()))) { [weak self] in
            guard let self else { return }
            self.machine.tick(now: self.now())
        }
    }
}
#endif
```

`macos/Sources/Features/Extensions/HoverEdge.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// A hover-only area: reports the pointer entering and leaving, and never
/// takes clicks or scrolls, so the terminal under it keeps working.
struct HoverEdge: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh SidebarAutoHideTests && macos/skins-test.sh SidebarPreferencesTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 5: Use auto-hide in the layout**

Replace the struct in `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift` with:

```swift
/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, and the Claude usage bar below
/// both. An open overlay extension covers the terminal content; an open
/// sidebar extension grows out of the strip over the terminal's edge. With
/// auto-hide on, the terminal takes the full width and the strip slides in
/// over it from the right edge. The terminal never changes size for an
/// app or for the strip showing and hiding.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content
    @ObservedObject private var preferences = SidebarPreferences.shared
    @StateObject private var autoHide = SidebarAutoHideDriver()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                content()
                    .overlay {
                        if let ext = model.active, ext.presentation == .overlay {
                            ExtensionContentView(ext: ext, model: model)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topTrailing) { NotificationStackView() }
                    .overlay(alignment: .trailing) { trailingChrome }
                if !preferences.autoHide {
                    ExtensionSidebarView(model: model)
                }
            }
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
        .animation(.easeOut(duration: 0.18), value: autoHide.isVisible)
        .onChange(of: model.active) { active in autoHide.appChanged(open: active != nil) }
        .onChange(of: preferences.autoHide) { _ in autoHide.reset(appOpen: model.active != nil) }
    }

    /// Over the terminal's right edge: the open sidebar extension, and with
    /// auto-hide the strip itself plus the hover edge that reveals it.
    @ViewBuilder private var trailingChrome: some View {
        if preferences.autoHide {
            ZStack(alignment: .trailing) {
                HoverEdge { autoHide.pointer(.edge, inside: $0) }
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    sidebarPanel
                    ExtensionSidebarView(model: model)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: -2)
                }
                .onHover { autoHide.pointer(.sidebar, inside: $0) }
                .offset(x: autoHide.isVisible ? 0 : ExtensionSidebarView.width + 16)
            }
        } else {
            sidebarPanel
        }
    }

    /// The open sidebar extension, flush against the strip.
    @ViewBuilder private var sidebarPanel: some View {
        if let ext = model.active, case .sidebar(let width) = ext.presentation {
            ExtensionContentView(ext: ext, model: model)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                .shadow(color: .black.opacity(0.35), radius: 12, x: -4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

- [ ] **Step 6: Build and re-run the sidebar suites**

Run: `macos/skins-test.sh ExtensionSidebarModelTests && macos/skins-test.sh SidebarAutoHideTests`
Expected: `** TEST SUCCEEDED **` for both (this also compiles the layout).

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Extensions/SidebarPreferences.swift macos/Sources/Features/Extensions/SidebarAutoHide.swift \
  macos/Sources/Features/Extensions/HoverEdge.swift macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift \
  macos/Tests/Extensions/SidebarAutoHideTests.swift macos/Tests/Extensions/SidebarPreferencesTests.swift
git commit -m "lostty: the sidebar can hide until the pointer reaches the right edge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Lostty Settings window

**Files:**
- Modify: `macos/Sources/Features/Settings/SettingsView.swift`
- Create: `macos/Sources/Features/Settings/SettingsUI.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift:343-346`

**Interfaces:**
- Consumes: `SidebarPreferences.shared` (Task 7).
- Produces: `SettingsUI.installMenuItem(after:)`, `SettingsUI.show()`.

- [ ] **Step 1: Replace the placeholder view**

Replace all of `macos/Sources/Features/Settings/SettingsView.swift` with:

```swift
#if os(macOS)
import SwiftUI

/// Lostty Settings: preferences that live in the app rather than the
/// config file.
struct SettingsView: View {
    @ObservedObject var sidebar: SidebarPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Sidebar") {
                    Toggle("Automatically hide sidebar", isOn: $sidebar.autoHide)
                    Text("Shows when you move the pointer to the window's right edge. "
                         + "Stays open while an app is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("Terminal settings live in $HOME/.config/ghostty/config.ghostty "
                 + "(Lostty → Preferences… opens it).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(sidebar: SidebarPreferences(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
```

- [ ] **Step 2: Add the window and menu item**

`macos/Sources/Features/Settings/SettingsUI.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// "Lostty Settings…" in the app menu, and its window. ⌘, (Preferences…)
/// still opens the config file.
@MainActor
enum SettingsUI {
    private static var window: NSWindow?

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Lostty Settings…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(sidebar: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "Lostty Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { SettingsUI.show() }
    }
}
#endif
```

- [ ] **Step 3: Install it**

In `macos/Sources/App/macOS/AppDelegate.swift`, directly after the line `PhoneAccessUI.installMenuItem(after: menuOpenConfig)` add:

```swift
        // Lostty Settings (sidebar auto-hide), right after Preferences….
        SettingsUI.installMenuItem(after: menuOpenConfig)
```

(Each call inserts directly after "Preferences…", so the last one installed comes first.)

- [ ] **Step 4: Build**

Run: `macos/skins-test.sh SidebarPreferencesTests`
Expected: `** TEST SUCCEEDED **` (compiles the app).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Settings/SettingsView.swift macos/Sources/Features/Settings/SettingsUI.swift \
  macos/Sources/App/macOS/AppDelegate.swift
git commit -m "lostty: a Lostty Settings window with the sidebar auto-hide toggle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Live inputs and BranchesModel

**Files:**
- Create: `macos/Sources/Features/Branches/SessionLocator.swift`
- Create: `macos/Sources/Features/Branches/RepoWatcher.swift`
- Create: `macos/Sources/Features/Branches/BranchesModel.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`
- Test: `macos/Tests/Branches/SessionLocatorTests.swift`
- Test: `macos/Tests/Branches/RepoWatcherTests.swift`
- Test: `macos/Tests/Branches/BranchesModelTests.swift`
- Test: `macos/Tests/Extensions/ExtensionSidebarModelTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–6; `ClaudeRuntime.shared.phases/awaiting` (`Features/Claude/ClaudeRuntime.swift`), `ClaudeUsageRuntime.shared.sessions` (`Features/Claude/ClaudeUsage.swift:92`), `SkinsRuntime.shared.manager.$panes`, `TerminalController.all`, `SurfaceView.pwd/title/id`, `TmuxClient`, `TmuxOwnership.available`, `ProcessLiveness.isAlive`, `AppDelegate.findSurface(forUUID:)`.
- Produces:
  - `PhonePanes.format`, `PhonePanes.activePaths(_:) -> [String: String]`
  - `SessionLocator.panes() -> [BranchSession]`, `SessionLocator.agentState(phase:awaiting:claudeOpen:) -> AgentState?`, `SessionLocator.phoneSessions() -> [BranchSession]`
  - `RepoWatcher.Change { case refs, index }`, `RepoWatcher.classify(_:) -> Change?`, `RepoWatcher(gitDir:latency:onChange:)`
  - `BranchesModel` with `Status`, `SummaryState`, `ClaudeLookup`, `Environment`, `@Published status/snapshot/sections/refreshFailed/refreshing/expanded/details/summaryStates/claude`, `open(focused:) -> Task<Void, Never>` (discardable), `close()`, `focusChanged(_:)`, `setFocus(_:) async`, `reload() async`, `toggle(_:)`, `loadDetails(_:) async`, `summary(for:)`, `summarize(_:)`, `cancelSummary(_:)`, `canSummarize`, `isOpen`
  - `ExtensionSidebarModel.branches: BranchesModel`, `ExtensionSidebarModel.init(branches:)`

- [ ] **Step 1: Write the failing tests for SessionLocator and RepoWatcher**

`macos/Tests/Branches/SessionLocatorTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SessionLocatorTests {
    @Test func phonePanesMapSessionsToTheirActivePanesFolder() {
        let output = """
        $1\t0\t/r/other
        $1\t1\t/r/repo
        $2\t1\t/r/two with space
        bad line
        $3\t1\t

        """
        #expect(PhonePanes.activePaths(output) == ["$1": "/r/repo", "$2": "/r/two with space"])
    }

    @Test func agentStatePrefersWaitingThenWorkingThenIdle() {
        #expect(SessionLocator.agentState(phase: true, awaiting: true, claudeOpen: true) == .waiting)
        #expect(SessionLocator.agentState(phase: true, awaiting: false, claudeOpen: true) == .working)
        #expect(SessionLocator.agentState(phase: false, awaiting: false, claudeOpen: true) == .idle)
        #expect(SessionLocator.agentState(phase: false, awaiting: false, claudeOpen: false) == nil)
    }
}
#endif
```

`macos/Tests/Branches/RepoWatcherTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct RepoWatcherTests {
    @Test func classifiesGitDirChanges() {
        #expect(RepoWatcher.classify("/r/.git/refs/heads/main") == .refs)
        #expect(RepoWatcher.classify("/r/.git/HEAD") == .refs)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/HEAD") == .refs)
        #expect(RepoWatcher.classify("/r/.git/index") == .index)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/index") == .index)
        #expect(RepoWatcher.classify("/r/.git/objects/ab/cdef") == nil)
        #expect(RepoWatcher.classify("/r/.git/logs/HEAD") == nil)
        #expect(RepoWatcher.classify("/r/.git/refs/heads/main.lock") == nil)
    }

    @Test func reportsACommit() async throws {
        let repo = try TempRepo.make()
        var changes: Set<RepoWatcher.Change> = []
        let watcher = try #require(RepoWatcher(gitDir: repo.root + "/.git", latency: 0.1) { changes.formUnion($0) })
        try await Task.sleep(nanoseconds: 300_000_000)
        try repo.commit("second")
        for _ in 0..<50 where !changes.contains(.refs) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(changes.contains(.refs))
        _ = watcher
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh SessionLocatorTests`
Expected: FAIL with `cannot find 'PhonePanes' in scope`.

- [ ] **Step 3: Implement SessionLocator and RepoWatcher**

`macos/Sources/Features/Branches/SessionLocator.swift`:

```swift
#if os(macOS)
import AppKit
import Foundation

/// Where each tmux session's active pane is, from `list-panes -a`.
enum PhonePanes {
    static let format = "#{session_id}\t#{pane_active}\t#{pane_current_path}"

    /// session id → its active pane's folder.
    static func activePaths(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, f[0].hasPrefix("$"), !f[2].isEmpty else { continue }
            if f[1] == "1" || result[f[0]] == nil { result[f[0]] = f[2] }
        }
        return result
    }
}

/// The sessions the Branches panel places on branches.
enum SessionLocator {
    /// Every pane in every terminal window that has reported its folder.
    @MainActor
    static func panes() -> [BranchSession] {
        let claude = ClaudeRuntime.shared
        let usage = ClaudeUsageRuntime.shared
        return TerminalController.all.flatMap { controller in
            controller.surfaceTree.compactMap { view -> BranchSession? in
                guard let pwd = view.pwd, !pwd.isEmpty else { return nil }
                let title = view.title.isEmpty ? (pwd as NSString).lastPathComponent : view.title
                let agent = agentState(
                    phase: claude.phases[view.id] != nil,
                    awaiting: claude.awaiting.contains(view.id),
                    claudeOpen: usage.sessions.contains(view.id))
                return BranchSession(origin: .pane(view.id), title: title, pwd: pwd, agent: agent)
            }
        }
    }

    static func agentState(phase: Bool, awaiting: Bool, claudeOpen: Bool) -> AgentState? {
        if awaiting { return .waiting }
        if phase { return .working }
        if claudeOpen { return .idle }
        return nil
    }

    /// Tmux sessions no running Lostty shows (started on the phone), at
    /// their active pane's folder. Blocking.
    static func phoneSessions() -> [BranchSession] {
        let client = TmuxClient()
        let sessions = TmuxOwnership.available(client.sessions(), isAlive: ProcessLiveness.isAlive)
        guard !sessions.isEmpty, let output = client.run(["list-panes", "-a", "-F", PhonePanes.format]) else { return [] }
        let paths = PhonePanes.activePaths(output)
        return sessions.compactMap { session in
            paths[session.id].map {
                BranchSession(origin: .phone(sessionID: session.id), title: session.name, pwd: $0, agent: nil)
            }
        }
    }
}
#endif
```

`macos/Sources/Features/Branches/RepoWatcher.swift`:

```swift
#if os(macOS)
import CoreServices
import Foundation

/// Watches a repo's shared git directory (refs, HEAD, every worktree's
/// HEAD and index) while the Branches panel is open. Events are coalesced
/// over `latency`. Stops when released.
final class RepoWatcher {
    enum Change: Hashable {
        /// Branches, HEADs or rebase state moved: re-read the repo.
        case refs
        /// Only the staging area changed: refresh uncommitted-change counts.
        case index
    }

    /// nil for churn the panel doesn't show (objects, reflogs, lock files).
    static func classify(_ path: String) -> Change? {
        let name = (path as NSString).lastPathComponent
        if path.contains("/objects/") || path.contains("/logs/") || name.hasSuffix(".lock") { return nil }
        return name == "index" ? .index : .refs
    }

    private var stream: FSEventStreamRef?
    private let onChange: @MainActor (Set<Change>) -> Void

    init?(gitDir: String, latency: TimeInterval = 0.3, onChange: @escaping @MainActor (Set<Change>) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let changes = Set(list.compactMap(RepoWatcher.classify))
            guard !changes.isEmpty else { return }
            MainActor.assumeIsolated { watcher.onChange(changes) }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [gitDir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
#endif
```

- [ ] **Step 4: Run them to verify they pass**

Run: `macos/skins-test.sh SessionLocatorTests && macos/skins-test.sh RepoWatcherTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 5: Write the failing BranchesModel tests**

`macos/Tests/Branches/BranchesModelTests.swift`:

```swift
#if os(macOS)
import Combine
import Foundation
import Testing
@testable import Ghostty

/// Scripted inputs for a BranchesModel.
@MainActor
final class FakeBranchesWorld {
    var pwds: [UUID: String] = [:]
    /// pwd prefix → location.
    var repos: [String: RepoLocation] = [:]
    /// root → snapshots to hand out in order; the last repeats. nil = git failed.
    var snapshots: [String: [RepoSnapshot?]] = [:]
    var panes: [BranchSession] = []
    var claude: String? = "/fake/claude"
    var summaryResult: Result<String, SummaryError> = .success("Adds X.")
    var slowPwd: String?
    /// Holds a locate of `slowPwd` until opened.
    let gate = Gate()
    var watching: [String] = []
    let changes = PassthroughSubject<Void, Never>()
    let cache: SummaryCache

    init() throws {
        cache = SummaryCache(url: URL(fileURLWithPath: try TempRepo.makeDirectory()).appendingPathComponent("s.json"))
    }

    func environment() -> BranchesModel.Environment {
        let repos = repos
        let slowPwd = slowPwd
        let gate = gate
        let claude = claude
        let summaryResult = summaryResult
        let store = SnapshotQueue(snapshots)
        return BranchesModel.Environment(
            pwd: { [unowned self] in self.pwds[$0] },
            locate: { pwd in
                if pwd == slowPwd { gate.enterAndWait() }
                return repos.first { pwd.hasPrefix($0.key) }?.value
            },
            read: { location, _ in store.next(location.root) },
            details: { _, _, _, _ in BranchDetails(vsBase: nil, changedFiles: 3, dirtyCount: 1) },
            panes: { [unowned self] in self.panes },
            phoneSessions: { [] },
            locateClaude: { claude },
            summarize: { _, _, _, _, _ in summaryResult },
            watch: { [unowned self] dir, _ in self.watching.append(dir); return NSObject() },
            changes: { [unowned self] in self.changes.eraseToAnyPublisher() },
            phoneInterval: 3600,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            cache: cache)
    }
}

/// Lets a test hold a background call until it says go.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entered = false

    var hasEntered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    func enterAndWait() {
        lock.lock()
        entered = true
        lock.unlock()
        semaphore.wait()
    }

    func open() { semaphore.signal() }
}

/// Hands out each root's snapshots in order, repeating the last.
final class SnapshotQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [RepoSnapshot?]]
    init(_ queues: [String: [RepoSnapshot?]]) { self.queues = queues }
    func next(_ root: String) -> RepoSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard var queue = queues[root], let first = queue.first else { return nil }
        if queue.count > 1 { queue.removeFirst(); queues[root] = queue }
        return first
    }
}

@MainActor
struct BranchesModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ root: String, branches: [String] = ["main", "feat"]) -> RepoSnapshot {
        RepoSnapshot(
            root: root, commonDir: root + "/.git", base: "main",
            branches: branches.map {
                BranchInfo(name: $0, tip: "\($0)-tip", lastCommit: now, subject: "s", upstream: .none, vsBase: nil)
            },
            worktrees: [Worktree(path: root, head: "h", branch: "main", rebasing: nil, isMain: true)])
    }

    private func world(pane: UUID, pwd: String = "/a/src") throws -> FakeBranchesWorld {
        let world = try FakeBranchesWorld()
        world.pwds[pane] = pwd
        world.repos["/a"] = RepoLocation(root: "/a", commonDir: "/a/.git")
        world.repos["/b"] = RepoLocation(root: "/b", commonDir: "/b/.git")
        world.snapshots["/a"] = [snapshot("/a")]
        world.snapshots["/b"] = [snapshot("/b")]
        return world
    }

    @Test func noFocusedPane() async throws {
        let model = BranchesModel(env: try FakeBranchesWorld().environment())
        await model.open(focused: nil).value
        #expect(model.status == .noPane)
    }

    @Test func aPaneOutsideARepo() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane, pwd: "/elsewhere").environment())
        await model.open(focused: pane).value
        #expect(model.status == .notARepo)
    }

    @Test func loadsTheRepoAndPlacesSessions() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.panes = [BranchSession(origin: .pane(pane), title: "zsh", pwd: "/a/src", agent: .working)]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        #expect(model.status == .loaded)
        #expect(model.snapshot?.root == "/a")
        #expect(model.sections.active.map(\.id) == ["main"])
        #expect(model.sections.active[0].sessions.first?.agent == .working)
        #expect(world.watching == ["/a/.git"])
    }

    @Test func keepsLastSnapshotWhenRefreshFails() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.snapshots["/a"] = [snapshot("/a"), nil]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.reload()
        #expect(model.status == .loaded)
        #expect(model.refreshFailed)
        #expect(model.snapshot?.root == "/a")
    }

    @Test func aFirstLoadFailureShowsFailed() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.snapshots["/a"] = [nil]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        #expect(model.status == .failed)
    }

    @Test func laterFocusWinsOverSlowerEarlierLoad() async throws {
        let slow = UUID()
        let fast = UUID()
        let world = try world(pane: slow, pwd: "/a/slow")
        world.pwds[fast] = "/b/src"
        world.slowPwd = "/a/slow"
        let model = BranchesModel(env: world.environment())
        await model.open(focused: nil).value
        let first = Task { await model.setFocus(slow) }
        while !world.gate.hasEntered { try await Task.sleep(nanoseconds: 10_000_000) }
        await model.setFocus(fast)
        world.gate.open()
        await first.value
        #expect(model.snapshot?.root == "/b")
    }

    @Test func expandingARowLoadsItsDetails() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane).environment())
        await model.open(focused: pane).value
        model.toggle("feat")
        #expect(model.expanded == ["feat"])
        await model.loadDetails("feat")
        #expect(model.details["feat"]?.changedFiles == 3)
        model.toggle("feat")
        #expect(model.expanded.isEmpty)
    }

    @Test func summarizeStoresTheSummary() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        #expect(model.canSummarize)
        await model.summarizeNow("feat")
        #expect(model.summaryStates["feat"] == nil)
        #expect(model.summary(for: "feat")?.text == "Adds X.")
        #expect(model.summary(for: "feat")?.tip == "feat-tip")
    }

    @Test func aFailedSummaryShowsWhy() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.summaryResult = .failure(.failed("Not logged in"))
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        await model.summarizeNow("feat")
        #expect(model.summaryStates["feat"] == .failed("Not logged in"))
    }

    @Test func noClaudeMeansNoSummaries() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.claude = nil
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        #expect(model.canSummarize == false)
        await model.summarizeNow("feat")
        #expect(model.summary(for: "feat") == nil)
    }

    @Test func closingStopsWatchingAndResets() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane).environment())
        await model.open(focused: pane).value
        model.close()
        #expect(model.status == .closed)
        #expect(model.isOpen == false)
        #expect(model.snapshot == nil)
    }
}
#endif
```

Replace `macos/Tests/Extensions/ExtensionSidebarModelTests.swift` so no test opens Branches with the live environment (which would start a login shell and call tmux):

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    /// A sidebar whose Branches model reads a scripted world.
    private func makeModel() throws -> (ExtensionSidebarModel, BranchesModel) {
        let branches = BranchesModel(env: try FakeBranchesWorld().environment())
        return (ExtensionSidebarModel(branches: branches), branches)
    }

    @Test func startsWithNothingOpen() throws {
        let (model, _) = try makeModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() throws {
        let (model, _) = try makeModel()
        model.select(.skins)
        #expect(model.active == .skins)
        model.select(.skins)
        #expect(model.active == nil)
    }

    @Test func clickingAnotherIconSwitchesToIt() throws {
        let (model, _) = try makeModel()
        model.select(.branches)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func closeLeavesAnyOpenApp() throws {
        let (model, _) = try makeModel()
        model.select(.branches)
        model.close()
        #expect(model.active == nil)
    }

    @Test func sidebarOrderIsBranchesThenSkins() {
        #expect(LosttyExtension.allCases == [.branches, .skins])
        #expect(LosttyExtension.branches.title == "Branches")
        #expect(LosttyExtension.skins.title == "Skins")
    }

    @Test func branchesOpensInTheSidebarAndSkinsOverTheTerminal() {
        #expect(LosttyExtension.branches.presentation == .sidebar(width: 340))
        #expect(LosttyExtension.skins.presentation == .overlay)
    }

    @Test func tracksTheFocusedPane() throws {
        let (model, _) = try makeModel()
        let pane = UUID()
        model.focusedSurfaceID = pane
        #expect(model.focusedSurfaceID == pane)
    }

    @Test func openingBranchesOpensItsModelAndLeavingClosesIt() throws {
        let (model, branches) = try makeModel()
        model.select(.branches)
        #expect(branches.isOpen)
        model.select(.skins)
        #expect(branches.isOpen == false)
    }
}
#endif
```

- [ ] **Step 6: Run them to verify they fail**

Run: `macos/skins-test.sh BranchesModelTests`
Expected: FAIL with `cannot find 'BranchesModel' in scope`.

- [ ] **Step 7: Implement BranchesModel**

`macos/Sources/Features/Branches/BranchesModel.swift`:

```swift
#if os(macOS)
import AppKit
import Combine
import Foundation

/// What one window's Branches panel shows. Does nothing until opened, and
/// stops watching when closed.
@MainActor
final class BranchesModel: ObservableObject {
    enum Status: Equatable {
        case closed
        case noPane
        case notARepo
        case loading
        case loaded
        /// The first read of this repo failed.
        case failed
    }

    enum SummaryState: Equatable {
        case running
        case failed(String)
    }

    enum ClaudeLookup: Equatable {
        case unknown
        case found(String)
        case missing
    }

    /// Everything the model reads from the outside world, so tests can
    /// script it. `live` is the app's.
    struct Environment {
        var pwd: @MainActor (UUID) -> String?
        var locate: @Sendable (String) -> RepoLocation?
        var read: @Sendable (RepoLocation, Date) -> RepoSnapshot?
        var details: @Sendable (BranchInfo, String?, Worktree?, String) -> BranchDetails
        var panes: @MainActor () -> [BranchSession]
        var phoneSessions: @Sendable () -> [BranchSession]
        var locateClaude: @Sendable () -> String?
        var summarize: @Sendable (String, String, String, String, RunHandle) -> Result<String, SummaryError>
        var watch: @MainActor (String, @escaping @MainActor (Set<RepoWatcher.Change>) -> Void) -> AnyObject?
        /// Fires when panes, their folders or agent states change.
        var changes: @MainActor () -> AnyPublisher<Void, Never>
        var phoneInterval: TimeInterval
        var now: () -> Date
        var cache: SummaryCache

        static var live: Environment {
            Environment(
                pwd: { (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: $0)?.pwd },
                locate: { RepoReader.locate(pwd: $0) },
                read: { RepoReader.read($0, now: $1) },
                details: { RepoReader.details(for: $0, base: $1, worktree: $2, in: $3) },
                panes: { SessionLocator.panes() },
                phoneSessions: { SessionLocator.phoneSessions() },
                locateClaude: { ClaudeCLI.locate() },
                summarize: { BranchSummarizer.run(branch: $0, base: $1, root: $2, claude: $3, handle: $4) },
                watch: { RepoWatcher(gitDir: $0, onChange: $1) },
                changes: {
                    Publishers.Merge4(
                        ClaudeRuntime.shared.$phases.map { _ in () },
                        ClaudeRuntime.shared.$awaiting.map { _ in () },
                        ClaudeUsageRuntime.shared.$sessions.map { _ in () },
                        SkinsRuntime.shared.manager.$panes.map { _ in () })
                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                    .eraseToAnyPublisher()
                },
                phoneInterval: 5,
                now: Date.init,
                cache: .shared)
        }
    }

    @Published private(set) var status: Status = .closed
    @Published private(set) var snapshot: RepoSnapshot?
    @Published private(set) var sections: BranchSections = .empty
    /// A refresh failed; the last snapshot is still showing.
    @Published private(set) var refreshFailed = false
    @Published private(set) var refreshing = false
    @Published private(set) var expanded: Set<String> = []
    @Published private(set) var details: [String: BranchDetails] = [:]
    @Published private(set) var summaryStates: [String: SummaryState] = [:]
    @Published private(set) var claude: ClaudeLookup = .unknown

    private(set) var isOpen = false
    private let env: Environment
    private var focused: UUID?
    private var lastPwd: String?
    private var location: RepoLocation?
    private var focusGeneration = 0
    private var loading = false
    private var reloadAgain = false
    private var watcher: AnyObject?
    private var phone: [BranchSession] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var phoneTimer: Timer?
    private var runs: [String: RunHandle] = [:]

    init(env: Environment = .live) {
        self.env = env
    }

    var canSummarize: Bool {
        if case .found = claude { return true }
        return false
    }

    // MARK: Opening and focus

    /// Starts following the window's focused pane. The returned task finishes
    /// once that pane's repo is shown (tests wait on it).
    @discardableResult
    func open(focused: UUID?) -> Task<Void, Never> {
        guard !isOpen else { return Task {} }
        isOpen = true
        status = .loading
        env.changes()
            .sink { [weak self] _ in self?.sessionsChanged() }
            .store(in: &subscriptions)
        phoneTimer = Timer.scheduledTimer(withTimeInterval: env.phoneInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPhoneSessions() }
        }
        refreshPhoneSessions()
        Task { await lookUpClaude() }
        return Task { await setFocus(focused) }
    }

    func close() {
        isOpen = false
        focusGeneration += 1
        subscriptions.removeAll()
        phoneTimer?.invalidate()
        phoneTimer = nil
        watcher = nil
        location = nil
        lastPwd = nil
        snapshot = nil
        sections = .empty
        expanded = []
        details = [:]
        refreshFailed = false
        status = .closed
    }

    func focusChanged(_ pane: UUID?) {
        Task { await setFocus(pane) }
    }

    /// Shows the repo of `pane`. A later call wins over an earlier one
    /// still finding its repo.
    func setFocus(_ pane: UUID?) async {
        guard isOpen else { return }
        focused = pane
        focusGeneration += 1
        let generation = focusGeneration
        guard let pane, let pwd = env.pwd(pane), !pwd.isEmpty else {
            show(location: nil, status: .noPane)
            return
        }
        lastPwd = pwd
        let locate = env.locate
        let found = await Task.detached { locate(pwd) }.value
        guard isOpen, generation == focusGeneration else { return }
        guard let found else {
            show(location: nil, status: .notARepo)
            return
        }
        guard found != location else { return }
        show(location: found, status: .loading)
        watcher = env.watch(found.commonDir) { [weak self] changes in self?.repoChanged(changes) }
        await reload()
    }

    private func show(location: RepoLocation?, status: Status) {
        if location != self.location {
            watcher = nil
            snapshot = nil
            sections = .empty
            expanded = []
            details = [:]
            refreshFailed = false
        }
        self.location = location
        self.status = status
    }

    // MARK: Reading the repo

    /// Re-reads the current repo. A call while a read runs makes that read
    /// go again when it finishes, so a burst of changes costs two reads.
    func reload() async {
        guard location != nil else { return }
        if loading {
            reloadAgain = true
            return
        }
        loading = true
        refreshing = true
        defer {
            loading = false
            refreshing = false
        }
        repeat {
            reloadAgain = false
            guard let target = location else { break }
            let read = env.read
            let now = env.now()
            let result = await Task.detached { read(target, now) }.value
            guard location == target else {
                reloadAgain = true
                continue
            }
            if let result {
                snapshot = result
                refreshFailed = false
                status = .loaded
                rebuildSections()
                for name in expanded { Task { await loadDetails(name) } }
            } else if snapshot == nil {
                status = .failed
            } else {
                refreshFailed = true
            }
        } while reloadAgain
    }

    private func repoChanged(_ changes: Set<RepoWatcher.Change>) {
        if changes.contains(.refs) {
            Task { await reload() }
        } else {
            for name in expanded { Task { await loadDetails(name) } }
        }
    }

    private func sessionsChanged() {
        guard isOpen else { return }
        if let focused, env.pwd(focused) != lastPwd {
            Task { await setFocus(focused) }
        }
        rebuildSections()
    }

    private func refreshPhoneSessions() {
        let fetch = env.phoneSessions
        Task {
            let sessions = await Task.detached { fetch() }.value
            guard isOpen, sessions != phone else { return }
            phone = sessions
            rebuildSections()
        }
    }

    private func rebuildSections() {
        guard let snapshot else {
            sections = .empty
            return
        }
        let placement = SessionPlacement.assign(env.panes() + phone, worktrees: snapshot.worktrees)
        sections = BranchSections.build(snapshot, placement: placement, now: env.now())
    }

    // MARK: Rows

    func toggle(_ name: String) {
        if expanded.remove(name) == nil {
            expanded.insert(name)
            Task { await loadDetails(name) }
        }
    }

    func loadDetails(_ name: String) async {
        guard let snapshot, let branch = snapshot.branches.first(where: { $0.name == name }) else { return }
        let tree = snapshot.worktrees.first { $0.branch == name }
        let read = env.details
        let base = snapshot.base
        let root = snapshot.root
        let result = await Task.detached { read(branch, base, tree, root) }.value
        guard self.snapshot?.root == root else { return }
        details[name] = result
    }

    // MARK: Summaries

    func lookUpClaude() async {
        guard claude == .unknown else { return }
        let locate = env.locateClaude
        let path = await Task.detached { locate() }.value
        claude = path.map(ClaudeLookup.found) ?? .missing
    }

    func summary(for name: String) -> BranchSummary? {
        guard let snapshot else { return nil }
        return env.cache.summary(repo: snapshot.commonDir, branch: name)
    }

    func summarize(_ name: String) {
        Task { await summarizeNow(name) }
    }

    func summarizeNow(_ name: String) async {
        guard case .found(let claude) = claude, let snapshot, let base = snapshot.base, name != base,
              let branch = snapshot.branches.first(where: { $0.name == name }),
              summaryStates[name] != .running else { return }
        let handle = RunHandle()
        runs[name] = handle
        summaryStates[name] = .running
        let run = env.summarize
        let root = snapshot.root
        let result = await Task.detached { run(name, base, root, claude, handle) }.value
        guard runs[name] === handle else { return }
        runs[name] = nil
        switch result {
        case .success(let text):
            env.cache.store(
                BranchSummary(tip: branch.tip, text: text, createdAt: env.now()),
                repo: snapshot.commonDir, branch: name)
            summaryStates[name] = nil
        case .failure(.cancelled):
            summaryStates[name] = nil
        case .failure(let error):
            summaryStates[name] = .failed(error.message)
        }
    }

    func cancelSummary(_ name: String) {
        runs[name]?.cancel()
    }
}
#endif
```

- [ ] **Step 8: Wire it into the sidebar model**

In `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`, replace the body of `ExtensionSidebarModel` with:

```swift
@MainActor
final class ExtensionSidebarModel: ObservableObject {
    @Published private(set) var active: LosttyExtension? {
        didSet {
            guard active != oldValue else { return }
            if active == .branches {
                branches.open(focused: focusedSurfaceID)
            } else if oldValue == .branches {
                branches.close()
            }
        }
    }
    /// The window's focused (or last focused) pane, set by the controller.
    @Published var focusedSurfaceID: UUID? {
        didSet {
            if active == .branches, focusedSurfaceID != oldValue { branches.focusChanged(focusedSurfaceID) }
        }
    }
    /// The title bar's color (the top pane's background), set by the window.
    @Published var chromeColor: NSColor?

    /// The Branches panel's state; idle until Branches opens.
    let branches: BranchesModel

    init(branches: BranchesModel = BranchesModel()) {
        self.branches = branches
    }

    /// Clicking an icon opens its extension; clicking the open one closes it.
    func select(_ ext: LosttyExtension) {
        active = active == ext ? nil : ext
    }

    /// A panel's back button and Esc.
    func close() {
        active = nil
    }
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `macos/skins-test.sh BranchesModelTests && macos/skins-test.sh ExtensionSidebarModelTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/Features/Branches/SessionLocator.swift macos/Sources/Features/Branches/RepoWatcher.swift \
  macos/Sources/Features/Branches/BranchesModel.swift macos/Sources/Features/Extensions/ExtensionSidebarModel.swift \
  macos/Tests/Branches/SessionLocatorTests.swift macos/Tests/Branches/RepoWatcherTests.swift \
  macos/Tests/Branches/BranchesModelTests.swift macos/Tests/Extensions/ExtensionSidebarModelTests.swift
git commit -m "lostty: the Branches model follows the focused pane's repo and its sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The Branches panel and its actions

**Files:**
- Create: `macos/Sources/Helpers/PaneFocus.swift`
- Create: `macos/Sources/Features/Branches/BranchesActions.swift`
- Create: `macos/Sources/Features/Branches/BranchesFormat.swift`
- Modify: `macos/Sources/Features/Branches/BranchesPanel.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarView.swift` (content case)
- Modify: `macos/Sources/Features/MenuBar/LosttyStatusItem.swift:165-174`
- Modify: `macos/Sources/Features/Sessions/SessionsUI.swift`
- Test: `macos/Tests/Branches/BranchesFormatTests.swift`

**Interfaces:**
- Consumes: `BranchesModel` (Task 9), `BranchesHeader`, `PanelEscape` (Task 6), `LosttyTheme`, `SessionLaunch.attachCommand`, `TerminalController.newTab(_:from:withBaseConfig:)`, `AppDelegate.ghostty`, `AppDelegate.findSurface(forUUID:)`.
- Produces: `PaneFocus.focus(_ id: UUID) -> Bool`; `SessionsUI.openInTab(_ sessionID: String, from: NSWindow?, ghostty: Ghostty.App)`; `BranchesActions.open(_ session: BranchSession)`; `BranchesFormat.aheadBehind(_:) -> String?`, `BranchesFormat.upstream(_:) -> String`, `BranchesFormat.count(_:_:) -> String`, `BranchesFormat.initial(_:) -> String`; `BranchesPanel(model:onClose:)`.

- [ ] **Step 1: Write the failing format tests**

`macos/Tests/Branches/BranchesFormatTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct BranchesFormatTests {
    @Test func aheadBehind() {
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 2, behind: 1)) == "↑2 ↓1")
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 3, behind: 0)) == "↑3")
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 0, behind: 0)) == "even")
        #expect(BranchesFormat.aheadBehind(nil) == nil)
    }

    @Test func upstream() {
        #expect(BranchesFormat.upstream(.none) == "Not pushed")
        #expect(BranchesFormat.upstream(.gone(name: "origin/x")) == "origin/x was deleted")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 0, behind: 0)) == "Up to date with origin/x")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 2, behind: 0)) == "2 to push to origin/x")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 1, behind: 3)) == "1 to push, 3 to pull · origin/x")
    }

    @Test func counts() {
        #expect(BranchesFormat.count(1, "file") == "1 file")
        #expect(BranchesFormat.count(4, "file") == "4 files")
    }

    @Test func initials() {
        #expect(BranchesFormat.initial("zsh") == "Z")
        #expect(BranchesFormat.initial("✳ Claude") == "C")
        #expect(BranchesFormat.initial("") == "•")
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh BranchesFormatTests`
Expected: FAIL with `cannot find 'BranchesFormat' in scope`.

- [ ] **Step 3: Implement the format helpers**

`macos/Sources/Features/Branches/BranchesFormat.swift`:

```swift
#if os(macOS)
import Foundation

/// Text for the Branches rows. Pure.
enum BranchesFormat {
    static func aheadBehind(_ value: AheadBehind?) -> String? {
        guard let value else { return nil }
        if value.ahead == 0 && value.behind == 0 { return "even" }
        return [value.ahead > 0 ? "↑\(value.ahead)" : nil, value.behind > 0 ? "↓\(value.behind)" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    static func upstream(_ upstream: Upstream) -> String {
        switch upstream {
        case .none:
            return "Not pushed"
        case .gone(let name):
            return "\(name) was deleted"
        case .tracking(let name, 0, 0):
            return "Up to date with \(name)"
        case .tracking(let name, let ahead, 0):
            return "\(ahead) to push to \(name)"
        case .tracking(let name, 0, let behind):
            return "\(behind) to pull from \(name)"
        case .tracking(let name, let ahead, let behind):
            return "\(ahead) to push, \(behind) to pull · \(name)"
        }
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// The first letter of a pane title, skipping agent spinners and symbols.
    static func initial(_ title: String) -> String {
        guard let letter = title.first(where: \.isLetter) else { return "•" }
        return String(letter).uppercased()
    }

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
#endif
```

- [ ] **Step 4: Run them to verify they pass**

Run: `macos/skins-test.sh BranchesFormatTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add PaneFocus, openInTab and BranchesActions**

`macos/Sources/Helpers/PaneFocus.swift`:

```swift
#if os(macOS)
import AppKit

@MainActor
enum PaneFocus {
    /// Brings pane `id`'s window to the front and focuses the pane. False
    /// when no window shows it any more.
    @discardableResult
    static func focus(_ id: UUID) -> Bool {
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: id),
              let controller = surface.window?.windowController as? BaseTerminalController
        else { return false }
        NSApp.activate(ignoringOtherApps: true)
        surface.window?.makeKeyAndOrderFront(nil)
        controller.focusSurface(surface)
        return true
    }
}
#endif
```

In `macos/Sources/Features/MenuBar/LosttyStatusItem.swift`, replace `focusPane(_:)` with:

```swift
    @objc private func focusPane(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        PaneFocus.focus(id)
    }
```

In `macos/Sources/Features/Sessions/SessionsUI.swift`, replace `open(_:ghostty:)` with:

```swift
    /// Opens a window showing `session`. The launcher re-tags the session
    /// with the new pane and this Lostty.
    @MainActor static func open(_ session: TmuxSession, ghostty: Ghostty.App) {
        guard let config = attachConfig(session.id) else { return }
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }

    /// Opens session `sessionID` in a new tab of `window` (a new window when
    /// there is none).
    @MainActor static func openInTab(_ sessionID: String, from window: NSWindow?, ghostty: Ghostty.App) {
        guard let config = attachConfig(sessionID) else { return }
        _ = TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
    }

    private static func attachConfig(_ sessionID: String) -> Ghostty.SurfaceConfiguration? {
        guard let binary = Bundle.main.executableURL?.path else { return nil }
        var config = Ghostty.SurfaceConfiguration()
        config.command = SessionLaunch.attachCommand(binary: binary, sessionID: sessionID)
        return config
    }
```

`macos/Sources/Features/Branches/BranchesActions.swift`:

```swift
#if os(macOS)
import AppKit

/// What clicking a session in the Branches panel does.
@MainActor
enum BranchesActions {
    /// A pane comes to the front; a session only the phone shows opens in a
    /// new tab of this window.
    static func open(_ session: BranchSession) {
        switch session.origin {
        case .pane(let id):
            PaneFocus.focus(id)
        case .phone(let sessionID):
            guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
            SessionsUI.openInTab(sessionID, from: NSApp.keyWindow, ghostty: ghostty)
        }
    }
}
#endif
```

- [ ] **Step 6: Build the panel**

Replace `BranchesPanel` (keep `BranchesHeader` and `PanelEscape`) in `macos/Sources/Features/Branches/BranchesPanel.swift` with:

```swift
/// The Branches app, inside the widened sidebar.
struct BranchesPanel: View {
    @ObservedObject var model: BranchesModel
    let onClose: () -> Void
    @State private var showOlder = false

    var body: some View {
        VStack(spacing: 0) {
            BranchesHeader(
                title: model.snapshot?.name ?? "Branches",
                subtitle: model.snapshot?.base.map { "base \($0)" },
                busy: model.refreshing && model.status == .loaded,
                onClose: onClose)
            Divider().overlay(LosttyTheme.hairline)
            content
        }
        .modifier(PanelEscape(onClose: onClose))
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .closed, .loading:
            centered { ProgressView().controlSize(.small) }
        case .noPane:
            centered { note("Click a pane, then open Branches.") }
        case .notARepo:
            centered { note("This pane isn't in a git repo.") }
        case .failed:
            centered {
                VStack(spacing: 8) {
                    note("Couldn't read this repo.")
                    Button("Retry") { Task { await model.reload() } }
                }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if model.refreshFailed {
                    Text("Couldn't refresh")
                        .font(.system(size: 11))
                        .foregroundStyle(LosttyTheme.warning)
                        .padding(.horizontal, 12)
                }
                group("Active", model.sections.active)
                ForEach(model.sections.detached) { detached in
                    sectionTitle("Detached @ \(detached.sha)")
                    ForEach(detached.sessions) { SessionLine(session: $0) }
                }
                group("Branches", model.sections.recent)
                if !model.sections.older.isEmpty {
                    Button { showOlder.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showOlder ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Older (\(model.sections.older.count))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    if showOlder {
                        ForEach(model.sections.older) { BranchRowView(row: $0, model: model) }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [BranchRow]) -> some View {
        if !rows.isEmpty {
            sectionTitle(title)
            ForEach(rows) { BranchRowView(row: $0, model: model) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(LosttyTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(LosttyTheme.textSecondary)
            .multilineTextAlignment(.center)
    }

    private func centered<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        VStack { Spacer(); view(); Spacer() }
            .frame(maxWidth: .infinity)
            .padding(16)
    }
}

/// One branch: a compact line, and its details when expanded.
private struct BranchRowView: View {
    let row: BranchRow
    @ObservedObject var model: BranchesModel
    @State private var hovering = false

    private var expanded: Bool { model.expanded.contains(row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.toggle(row.id) } label: { line }
                .buttonStyle(.plain)
            if expanded { detail }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(expanded ? 0.06 : hovering ? 0.04 : 0)))
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
    }

    private var line: some View {
        HStack(spacing: 6) {
            Text(row.branch.name)
                .font(LosttyFont.mono(size: 12, weight: row.sessions.isEmpty ? .regular : .semibold))
                .foregroundStyle(LosttyTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isBase { tag("base", LosttyTheme.textSecondary) }
            if row.isRebasing { tag("rebasing", LosttyTheme.warning) }
            Spacer(minLength: 4)
            if !row.isBase, let text = BranchesFormat.aheadBehind(row.branch.vsBase ?? model.details[row.id]?.vsBase) {
                Text(text).font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary)
            }
            Text(BranchesFormat.relative.localizedString(for: row.branch.lastCommit, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(LosttyTheme.textSecondary)
                .lineLimit(1)
            HStack(spacing: -4) {
                ForEach(row.sessions.prefix(4)) { SessionAvatar(session: $0) }
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.branch.subject)
                .font(.system(size: 12))
                .foregroundStyle(LosttyTheme.textPrimary)
                .lineLimit(2)
            let details = model.details[row.id]
            VStack(alignment: .leading, spacing: 2) {
                if let path = row.worktreePath { fact("Worktree \((path as NSString).abbreviatingWithTildeInPath)") }
                fact(BranchesFormat.upstream(row.branch.upstream))
                if let files = details?.changedFiles, !row.isBase {
                    fact("\(BranchesFormat.count(files, "file")) changed vs \(model.snapshot?.base ?? "base")")
                }
                if let dirty = details?.dirtyCount, dirty > 0 {
                    fact("\(BranchesFormat.count(dirty, "uncommitted change"))")
                }
            }
            if !row.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(row.sessions) { SessionLine(session: $0) }
                }
            }
            if !row.isBase { SummaryBlock(row: row, model: model) }
        }
        .padding(.leading, 2)
    }

    private func fact(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary).lineLimit(1)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 0.5))
    }
}

/// The summary for one branch, and the button that asks for it.
private struct SummaryBlock: View {
    let row: BranchRow
    @ObservedObject var model: BranchesModel

    var body: some View {
        let cached = model.summary(for: row.id)
        let outdated = cached?.isOutdated(tip: row.branch.tip) ?? false
        VStack(alignment: .leading, spacing: 6) {
            if let cached {
                Text(cached.text)
                    .font(.system(size: 12))
                    .foregroundStyle(LosttyTheme.textPrimary.opacity(outdated ? 0.55 : 0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if outdated {
                    Text("Outdated: the branch has moved since.")
                        .font(.system(size: 10))
                        .foregroundStyle(LosttyTheme.warning)
                }
            }
            switch model.summaryStates[row.id] {
            case .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…").font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary)
                    Button("Cancel") { model.cancelSummary(row.id) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(LosttyTheme.danger)
                summarizeButton(cached == nil ? "Retry" : "Re-summarize")
            case nil:
                summarizeButton(cached == nil ? "Summarize" : outdated ? "Re-summarize" : "Summarize again")
            }
        }
    }

    private func summarizeButton(_ title: String) -> some View {
        Button(title) { model.summarize(row.id) }
            .controlSize(.small)
            .disabled(!model.canSummarize)
            .help(model.claude == .missing ? "Install Claude Code to summarize" : "Ask Claude what this branch does")
    }
}

/// A session in an expanded row: click to go to it.
private struct SessionLine: View {
    let session: BranchSession

    var body: some View {
        Button { BranchesActions.open(session) } label: {
            HStack(spacing: 6) {
                SessionAvatar(session: session)
                Text(session.title)
                    .font(.system(size: 12))
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if session.isPhone {
                    Text("phone").font(.system(size: 10)).foregroundStyle(LosttyTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.isPhone ? "Open in a new tab" : "Go to this pane")
    }
}

/// A session's initial (or a phone), with its agent's state as a dot.
private struct SessionAvatar: View {
    let session: BranchSession
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(LosttyTheme.surfaceRaised)
            Circle().strokeBorder(LosttyTheme.hairline, lineWidth: 1)
            if session.isPhone {
                Image(systemName: "iphone").font(.system(size: 8, weight: .semibold))
            } else {
                Text(BranchesFormat.initial(session.title)).font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(LosttyTheme.textPrimary)
        .frame(width: 18, height: 18)
        .overlay(alignment: .bottomTrailing) {
            if let agent = session.agent {
                Circle()
                    .fill(color(agent))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                    .opacity(agent == .working && pulse ? 0.35 : 1)
                    .offset(x: 2, y: 2)
                    .onAppear {
                        guard agent == .working else { return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
                    }
            }
        }
        .accessibilityLabel(label)
    }

    private func color(_ agent: AgentState) -> Color {
        switch agent {
        case .working: LosttyTheme.accent
        case .idle: LosttyTheme.success
        case .waiting: LosttyTheme.warning
        }
    }

    private var label: String {
        switch session.agent {
        case .working: "\(session.title), agent working"
        case .idle: "\(session.title), Claude idle"
        case .waiting: "\(session.title), agent waiting for you"
        case nil: session.title
        }
    }
}
```

In `macos/Sources/Features/Extensions/ExtensionSidebarView.swift`, change the `.branches` content case to:

```swift
        case .branches:
            BranchesPanel(model: model.branches, onClose: model.close)
```

- [ ] **Step 7: Build and run the Branches and sidebar suites**

Run: `macos/skins-test.sh BranchesFormatTests && macos/skins-test.sh BranchesModelTests && macos/skins-test.sh ExtensionSidebarModelTests`
Expected: `** TEST SUCCEEDED **` for all three.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Helpers/PaneFocus.swift macos/Sources/Features/Branches/BranchesActions.swift \
  macos/Sources/Features/Branches/BranchesFormat.swift macos/Sources/Features/Branches/BranchesPanel.swift \
  macos/Sources/Features/Extensions/ExtensionSidebarView.swift macos/Sources/Features/MenuBar/LosttyStatusItem.swift \
  macos/Sources/Features/Sessions/SessionsUI.swift macos/Tests/Branches/BranchesFormatTests.swift
git commit -m "lostty: the Branches panel lists branches, sessions, facts and summaries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Verify in the app, lint, and close out

**Files:**
- Modify: `docs/superpowers/specs/2026-10-12-branches-sidebar-design.md` (status line, deviations)

- [ ] **Step 1: Lint**

Run: `swiftlint lint --strict --fix macos/Sources/Features/Branches macos/Sources/Features/Extensions macos/Sources/Features/Settings macos/Sources/Helpers/ProcessRunner.swift macos/Sources/Helpers/PaneFocus.swift && swiftlint lint --strict macos/Sources/Features/Branches macos/Sources/Features/Extensions macos/Sources/Features/Settings`
Expected: no violations. Fix any by hand, re-run the affected suite.

- [ ] **Step 2: Run every new and touched suite**

Run each: `ProcessRunnerTests GitTests RepoParseTests RepoReaderTests SessionPlacementTests BranchSectionsTests SummaryCacheTests SummaryPromptTests ClaudeCLITests BranchSummarizerTests ExtensionSidebarModelTests SidebarAutoHideTests SidebarPreferencesTests SessionLocatorTests RepoWatcherTests BranchesModelTests BranchesFormatTests` with `macos/skins-test.sh <Suite>`.
Expected: every one `** TEST SUCCEEDED **`. If "test runner timed out", see memory note: an orphan tmux session with a dead `@lostty_owner` blocks the runner; disown it and re-run.

- [ ] **Step 3: Confirm the real `claude` flags once (tiny prompt)**

Run: `echo 'Reply with the word OK.' | claude -p --model haiku --tools "" --no-session-persistence --strict-mcp-config --setting-sources ""`
Expected: prints `OK` (or similar). If a flag is rejected, remove only that flag from `ClaudeCLI.arguments`, update `ClaudeCLITests.runsHeadlessWithNoToolsOnHaiku` to match, re-run `ClaudeCLITests`, and note the change in the spec.

- [ ] **Step 4: Build and launch the Debug app**

Run: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | tail -3 && open macos/build/Debug/Ghostty.app`
Expected: `** BUILD SUCCEEDED **`, the app opens.

- [ ] **Step 5: Check by hand against the spec's success criteria**

In the running app, with one window `cd`'d into this repo and a second window (or split) in `.claude/worktrees/mac-ui`:
1. The sidebar shows Branches (green) above Skins. Clicking Branches slides a 340pt panel out of the strip over the terminal; the terminal text does not reflow.
2. The panel header shows "lostty" and "base main". `branches` and `mac-ui` are under Active with an avatar each; the `mac-ui` row (expanded) shows its worktree path.
3. "‹ Apps" closes it; re-clicking the icon closes it; clicking inside the panel then pressing Esc closes it; pressing Esc with the terminal focused does not.
4. Run `git commit --allow-empty -m test` in the pane (then `git reset --soft HEAD~1`): the `branches` row's time updates within about a second.
5. Click a session line: its pane's window comes to the front and the pane is focused.
6. Open Skins while Branches is open: Branches closes, Skins covers the terminal.
7. Expand a non-base branch and click Summarize once: a spinner, then 2–4 sentences. Close and reopen the panel: the summary is still there. (This one costs tokens; do it once.)
8. Lostty → Lostty Settings…: toggle "Automatically hide sidebar" on. The strip slides away and the terminal widens once; moving the pointer to the right edge brings the strip back over the terminal; moving away hides it after about half a second; with Branches open it stays. Clicks and scrolling on the terminal's right edge still work. Toggle off: the strip is back beside the terminal.

Record anything that fails as a bug and fix it (systematic-debugging) before Step 6.

- [ ] **Step 6: Mark the spec implemented**

In `docs/superpowers/specs/2026-10-12-branches-sidebar-design.md`, change `Status: draft for review (2026-10-12)` to `Status: implemented (plan docs/superpowers/plans/2026-10-12-branches-sidebar.md)`, and add after the Decisions table:

```markdown
### Changes made during planning

- The agent badge is generic: Lostty can't tell Claude from Codex, and only
  knows "idle" for Claude (its usage reports). Working and waiting show for
  both.
- Settings open from a new "Lostty Settings…" app-menu item; ⌘,
  ("Preferences…") still opens the config file.
```

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs/2026-10-12-branches-sidebar-design.md
git commit -m "docs: Branches sidebar implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
