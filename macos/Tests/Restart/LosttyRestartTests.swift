#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct LosttyRestartTests {
    @Test func theReopenScriptWaitsThenOpensThisBundle() {
        let script = LosttyRestart.reopenScript(pid: 4242, bundle: "/Applications/Lostty (previous).app")
        #expect(script == "while kill -0 4242 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n '/Applications/Lostty (previous).app'")
    }

    @Test func theHelperRunsDetached() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString)")
        #expect(LosttyRestart.spawnDetached("echo ok > '\(marker.path)'"))
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { usleep(50_000) }
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// The helper outlives Lostty: it must not hold Lostty's files (a lock,
    /// say) after Lostty exits.
    @Test func theHelperDoesNotInheritDescriptors() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)")
        // Inheritable on purpose: the helper must close it anyway.
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(LosttyRestart.spawnDetached("sleep 3"))
        close(fd)
        let again = open(url.path, O_RDWR | O_CLOEXEC)
        defer { close(again) }
        #expect(flock(again, LOCK_EX | LOCK_NB) == 0)
    }

    @Test func restartingTwiceIsOnce() {
        LosttyRestart.isRestarting = false
        #expect(LosttyRestart.begin())
        #expect(!LosttyRestart.begin())
        LosttyRestart.isRestarting = false
    }

    // MARK: Hooks

    @Test func agentsWithAnyLosttyHooksAreRemembered() {
        let status: [HookAgent: ClaudeHooksStatus] = [.claude: .partial, .codex: .notInstalled]
        #expect(LosttyRestart.agentsWithHooks { status[$0] } == ["claude"])
    }

    @Test func onlyThoseOutOfDateAfterTheRestartAreReinstalled() {
        let status: [HookAgent: ClaudeHooksStatus] = [.claude: .partial, .codex: .partial]
        #expect(LosttyRestart.agentsToReinstall(had: ["claude"]) { status[$0] } == [.claude])
        let current: [HookAgent: ClaudeHooksStatus] = [.claude: .installed]
        #expect(LosttyRestart.agentsToReinstall(had: ["claude"]) { current[$0] }.isEmpty)
    }

    // MARK: A complete bundle

    @Test func aHalfCopiedBundleIsNotOneToOpen() throws {
        let fake = FileManager.default.temporaryDirectory.appendingPathComponent("Half-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: fake.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try Data("not a binary".utf8).write(to: fake.appendingPathComponent("Contents/MacOS/lostty"))
        #expect(!LosttyRestart.bundleIsComplete(atPath: fake.path))
        #expect(LosttyRestart.bundleIsComplete(atPath: Bundle.main.bundlePath))
    }

    // MARK: Test host

    @Test func theTestHostLeavesAHandoffAlone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restart-test-\(UUID().uuidString).json")
        try RestartHandoff(
            pid: 999_999, at: Date(), claude: [:], stayAwakeOn: true, stayAwakeUntil: nil, hookAgents: [], keepWindows: nil
        ).save(to: url)
        #expect(!LosttyRestart.resumeIfRestarted(from: url, environment: ["XCTestConfigurationFilePath": "/x"]))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func onlyWhileTheObserverIsOnAreItsConversationsHandedOver() {
        let pane = UUID()
        #expect(LosttyRestart.transcripts([pane: "/t.jsonl"], observes: true) == [pane.uuidString: "/t.jsonl"])
        #expect(LosttyRestart.transcripts([pane: "/t.jsonl"], observes: false) == nil)
    }

    @Test func anObserverThatIsOffIgnoresConversationsHandedOver() {
        let pane = UUID()
        let saved = [pane.uuidString: "/t.jsonl", "not a uuid": "/x.jsonl"]
        #expect(LosttyRestart.restoredTranscripts(saved, observes: true) == [pane: "/t.jsonl"])
        #expect(LosttyRestart.restoredTranscripts(saved, observes: false).isEmpty)
        #expect(LosttyRestart.restoredTranscripts(nil, observes: true).isEmpty)
    }
}
#endif
