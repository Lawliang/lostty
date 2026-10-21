#if os(macOS)
import Foundation
import Testing
@testable import Lostty

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
        // pwd -P prints the physical path (/private/var), which canonical() does not resolve.
        let physical = try #require(realpath(dir, nil))
        defer { free(physical) }
        let result = try #require(ProcessRunner.run("/bin/pwd", ["-P"], cwd: dir, timeout: 5))
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == String(cString: physical))
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

    @Test func canReplaceTheWholeEnvironment() throws {
        let result = try #require(ProcessRunner.run(
            "/usr/bin/env", [], environment: ["ONLY": "1"], inheritEnvironment: false, timeout: 5))
        #expect(result.stdout == "ONLY=1\n")
    }

    /// SessionWatcher's thread never returns to its autorelease pool; a run
    /// there mustn't leave its pipes open.
    @Test func closesItsPipesOnAThreadThatNeverDrains() async {
        let grown = await openFilesGrowth { _ = ProcessRunner.run("/usr/bin/true", [], timeout: 5) }
        #expect(grown < 20)
    }
}

/// How many more files are open after `body` runs 50 times on a thread
/// whose autorelease pool doesn't drain until it ends. Other tests running
/// at the same time can open a few.
func openFilesGrowth(_ body: @escaping @Sendable () -> Void) async -> Int {
    await withCheckedContinuation { done in
        Thread {
            let before = openFiles()
            for _ in 0..<50 { body() }
            done.resume(returning: openFiles() - before)
        }.start()
    }
}

private func openFiles() -> Int {
    (0..<getdtablesize()).filter { fcntl($0, F_GETFD) != -1 }.count
}
#endif
