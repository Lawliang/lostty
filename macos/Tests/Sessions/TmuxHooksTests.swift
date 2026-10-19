#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TmuxHooksTests {
    @Test func tmuxConfSetsEveryHook() throws {
        // macos/Tests/Sessions/<this file> → repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let conf = try String(
            contentsOf: root.appendingPathComponent("src/shell-integration/lostty-tmux/tmux.conf"), encoding: .utf8)
        for line in TmuxHooks.confLines {
            #expect(conf.contains(line + "\n"), "tmux.conf is missing: \(line)")
        }
    }

    @Test func confLinesSignalTheChannelKeepTheServerAndDontSaveClears() {
        #expect(TmuxHooks.confLines.first == "set-hook -g session-created 'wait-for -S lostty-changed'")
        #expect(TmuxHooks.confLines.suffix(2) == ["set -s exit-empty off", "set -g scroll-on-clear off"])
        #expect(TmuxHooks.confLines.count == 7)
    }

    @Test func launchSetsTheSameSettingsInOneCall() {
        let signal = "wait-for -S lostty-changed"
        #expect(TmuxHooks.setArgs == [
            "set-hook", "-g", "session-created", signal, ";",
            "set-hook", "-g", "session-closed", signal, ";",
            "set-hook", "-g", "session-renamed", signal, ";",
            "set-hook", "-g", "client-attached", signal, ";",
            "set-hook", "-g", "client-detached", signal, ";",
            "set-option", "-s", "exit-empty", "off", ";",
            "set-option", "-g", "scroll-on-clear", "off",
        ])
    }

    @Test func signallingNeverStartsAServerWithTheUsersConfig() {
        #expect(TmuxHooks.signalArgs == ["-f", "/dev/null", "wait-for", "-S", "lostty-changed"])
    }
}

struct SessionWatcherTests {
    @Test func aWaitThatFailsAtOncePauses() {
        #expect(SessionWatcher.pause(woke: false, waited: 0.05) == 5)
    }

    @Test func aWakeOrATimeoutWaitsAgainAtOnce() {
        #expect(SessionWatcher.pause(woke: true, waited: 0.01) == 0)
        #expect(SessionWatcher.pause(woke: false, waited: 600) == 0)
    }

    @Test func theWaitNeverStartsAServerWithTheUsersConfig() {
        #expect(SessionWatcher.waitArgs == ["-f", "/dev/null", "wait-for", "lostty-changed"])
    }
}
#endif
