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
}
#endif
