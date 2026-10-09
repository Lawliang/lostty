#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct ClaudeUsageTests {
    let pane = UUID()

    func makeDefaults() -> UserDefaults {
        let name = "ClaudeUsageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func decodesAFullReport() {
        let report = ClaudeUsageReport.decode(
            #"{"v":1,"ctx":{"used":84000,"size":200000},"five":{"pct":42.5,"reset":1760000000},"#
                + #""week":{"pct":17},"model":"Opus"}"#)
        #expect(report?.context == .init(used: 84000, size: 200000))
        #expect(report?.context?.percent == 42)
        #expect(report?.fiveHour == .init(percent: 42.5, resetsAt: Date(timeIntervalSince1970: 1_760_000_000)))
        #expect(report?.sevenDay == .init(percent: 17, resetsAt: nil))
        #expect(report?.model == "Opus")
    }

    @Test func rejectsOtherVersionsAndJunk() {
        #expect(ClaudeUsageReport.decode(#"{"v":2}"#) == nil)
        #expect(ClaudeUsageReport.decode("nope") == nil)
        #expect(ClaudeUsageReport.decode(#"{"v":1}"#) == ClaudeUsageReport())
        // A zero-size window is not a context.
        #expect(ClaudeUsageReport.decode(#"{"v":1,"ctx":{"used":5,"size":0}}"#)?.context == nil)
    }

    @Test func contextIsPerPaneAndLimitsAreShared() {
        let runtime = ClaudeUsageRuntime(defaults: makeDefaults())
        let other = UUID()
        runtime.userVarChanged(pane, name: "LOSTTY_USAGE", value: #"{"v":1,"ctx":{"used":50000,"size":200000},"five":{"pct":10}}"#)
        runtime.userVarChanged(other, name: "LOSTTY_USAGE", value: #"{"v":1,"five":{"pct":12}}"#)
        #expect(runtime.contexts[pane]?.percent == 25)
        #expect(runtime.contexts[other] == nil)
        #expect(runtime.percent(.session) == 12)
        #expect(runtime.percent(.weekly) == nil)
        #expect(runtime.percent(.weeklyFable) == nil)
    }

    @Test func aReportWithoutNumbersStillMarksASession() {
        let runtime = ClaudeUsageRuntime(defaults: makeDefaults())
        runtime.userVarChanged(pane, name: "LOSTTY_USAGE", value: #"{"v":1,"model":"Opus"}"#)
        #expect(runtime.sessions == [pane])
        #expect(runtime.contexts[pane] == nil)
        runtime.commandFinished(pane)
        #expect(runtime.sessions.isEmpty)
    }

    @Test func otherUserVarsAreIgnored() {
        let runtime = ClaudeUsageRuntime(defaults: makeDefaults())
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"ctx":{"used":1,"size":2}}"#)
        #expect(runtime.contexts.isEmpty)
    }

    @Test func finishedCommandForgetsThePaneContext() {
        let runtime = ClaudeUsageRuntime(defaults: makeDefaults())
        runtime.userVarChanged(pane, name: "LOSTTY_USAGE", value: #"{"v":1,"ctx":{"used":1,"size":2},"model":"Opus","week":{"pct":3}}"#)
        runtime.commandFinished(pane)
        #expect(runtime.contexts[pane] == nil)
        #expect(runtime.models[pane] == nil)
        // Plan limits are not the pane's.
        #expect(runtime.percent(.weekly) == 3)
    }

    @Test func aResetWindowCountsAsEmpty() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let runtime = ClaudeUsageRuntime(defaults: makeDefaults(), now: { clock })
        runtime.userVarChanged(pane, name: "LOSTTY_USAGE", value: #"{"v":1,"five":{"pct":80,"reset":2000}}"#)
        #expect(runtime.percent(.session) == 80)
        clock = Date(timeIntervalSince1970: 2_000)
        #expect(runtime.percent(.session) == 0)
    }

    @Test func trackedMetricAndLimitsSurviveARelaunch() {
        let defaults = makeDefaults()
        let first = ClaudeUsageRuntime(defaults: defaults)
        #expect(first.tracked == .session)
        first.tracked = .weekly
        first.userVarChanged(pane, name: "LOSTTY_USAGE", value: #"{"v":1,"week":{"pct":33,"reset":9999999999}}"#)
        let second = ClaudeUsageRuntime(defaults: defaults)
        #expect(second.tracked == .weekly)
        #expect(second.sevenDay?.percent == 33)
    }

    @Test func formatsTokensToTheNearestThousand() {
        #expect(ClaudeUsageFormat.thousands(49_600) == "50K")
        #expect(ClaudeUsageFormat.thousands(43_490) == "43K")
        #expect(ClaudeUsageFormat.thousands(300) == "0K")
        #expect(ClaudeUsageFormat.thousands(1_234_000) == "1,234K")
    }

    @Test func aTrackedContextFromBeforeFallsBackToTheSession() {
        let defaults = makeDefaults()
        defaults.set("context", forKey: "LosttyUsageTracked")
        #expect(ClaudeUsageRuntime(defaults: defaults).tracked == .session)
    }

    @Test func formatsResets() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ClaudeUsageFormat.reset(now.addingTimeInterval(2 * 3600 + 14 * 60), now: now) == "Resets in 2h 14m")
        #expect(ClaudeUsageFormat.reset(now.addingTimeInterval(59), now: now) == "Resets in 1m")
        #expect(ClaudeUsageFormat.reset(now, now: now) == "Reset")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 1970-01-02 09:00 UTC was a Friday.
        let friday = Date(timeIntervalSince1970: 24 * 3600 + 9 * 3600)
        let text = ClaudeUsageFormat.reset(friday, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        // The formatter puts a narrow no-break space before "AM".
        #expect(text.replacingOccurrences(of: "\u{202F}", with: " ") == "Resets Fri, 9 AM")
    }

    @Test func blocksShowAnyUseAndCapAtFull() {
        #expect(ClaudeUsageBlocks.filled(0) == 0)
        #expect(ClaudeUsageBlocks.filled(2) == 1)
        #expect(ClaudeUsageBlocks.filled(50) == 5)
        #expect(ClaudeUsageBlocks.filled(250) == 10)
    }

    @Test func blocksTurnAmberThenRed() {
        #expect(ClaudeUsageBlocks.fill(for: 50, accent: .blue) == .blue)
        #expect(ClaudeUsageBlocks.fill(for: 70, accent: .blue) != .blue)
        #expect(ClaudeUsageBlocks.fill(for: 95, accent: .blue) != ClaudeUsageBlocks.fill(for: 75, accent: .blue))
    }
}
#endif
