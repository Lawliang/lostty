#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct VoiceAutoSendTests {
    private let rule = String(repeating: "─", count: 40)
    private let footer = "  ⏵⏵ bypass permissions on (shift+tab to cycle)        ⏺ REC · tap to send"

    @Test func readsTheBarAndWordsWhileRecording() {
        let screen = [" ▐▛███▛█   Claude Code", rule, "❯ ▃", rule, footer].joined(separator: "\n")
        #expect(VoiceFrame.parse(screen) == VoiceFrame(words: "", ruleRow: 3, footerRow: 4))
        let talking = [rule, "❯ fix the menu bar so", "  it opens ▅", rule, footer].joined(separator: "\n")
        #expect(VoiceFrame.parse(talking) == VoiceFrame(words: "fix the menu bar so it opens", ruleRow: 3, footerRow: 4))
    }

    @Test func noFrameWhenNotRecording() {
        let screen = [rule, "❯ Try \"refactor AppDelegate.swift\"", rule, "  ⏵⏵ bypass permissions on"]
            .joined(separator: "\n")
        #expect(VoiceFrame.parse(screen) == nil)
    }

    @Test func noNewWordsCountsDownThenSends() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        #expect(watch.update(VoiceFrame(words: ""), now: start) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just"), now: start + 1) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 1.5) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 2) == .wait)
        #expect(watch.sendsAt == nil)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 2.5) == .wait)
        #expect(watch.sendsAt == start + 6.5)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 4) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 6) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 6.5) == .send)
    }

    @Test func newWordsCallTheCountdownOff() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix it"), now: start)
        _ = watch.update(VoiceFrame(words: "fix it"), now: start + 1)
        #expect(watch.sendsAt != nil)
        _ = watch.update(VoiceFrame(words: "fix it and also"), now: start + 2)
        #expect(watch.sendsAt == nil)
    }

    @Test func holdWaitsForMoreWords() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix it"), now: start)
        _ = watch.update(VoiceFrame(words: "fix it"), now: start + 1)
        watch.hold(now: start + 2)
        #expect(watch.update(VoiceFrame(words: "fix it"), now: start + 10) == .wait)
        #expect(watch.sendsAt == nil)
        _ = watch.update(VoiceFrame(words: "fix it now"), now: start + 11)
        _ = watch.update(VoiceFrame(words: "fix it now"), now: start + 12)
        #expect(watch.sendsAt == start + 16)
    }

    @Test func touchUpsAfterAHoldDontSend() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix the menu"), now: start)
        _ = watch.update(VoiceFrame(words: "fix the menu"), now: start + 1)
        watch.hold(now: start + 2)
        // The last word lands just after the hold, then Claude fixes punctuation.
        _ = watch.update(VoiceFrame(words: "fix the menu bar"), now: start + 2.5)
        _ = watch.update(VoiceFrame(words: "Fix the menu bar."), now: start + 5)
        for second in 6..<20 {
            #expect(watch.update(VoiceFrame(words: "Fix the menu bar."), now: start + Double(second)) == .wait)
        }
        #expect(watch.sendsAt == nil)
    }

    @Test func silenceFromTheStartNeverSends() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        for second in 0..<20 {
            #expect(watch.update(VoiceFrame(words: ""), now: start + Double(second)) == .wait)
        }
        #expect(watch.sendsAt == nil)
    }

    @Test func stopsWhenTheRecordingEnds() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        #expect(watch.update(nil, now: start + 4) == .wait)
        #expect(watch.update(nil, now: start + 6) == .stop)
        var recording = VoiceWatch(since: start)
        _ = recording.update(VoiceFrame(words: ""), now: start)
        #expect(recording.update(nil, now: start + 0.5) == .wait)
        #expect(recording.update(nil, now: start + 1.5) == .stop)
    }

    @Test func voiceKeysFollowClaudesKeybindings() {
        #expect(VoiceKeys.parse(nil) == [" "])
        let backtick = #"{"bindings":[{"context":"Chat","bindings":{"`":"voice:pushToTalk","space":null}}]}"#
        #expect(VoiceKeys.parse(Data(backtick.utf8)) == ["`"])
        let combo = #"{"bindings":[{"context":"Chat","bindings":{"meta+k":"voice:pushToTalk","space":null}}]}"#
        #expect(VoiceKeys.parse(Data(combo.utf8)).isEmpty)
        let elsewhere = #"{"bindings":[{"context":"Global","bindings":{"`":"voice:pushToTalk"}}]}"#
        #expect(VoiceKeys.parse(Data(elsewhere.utf8)) == [" "])
    }
}
#endif
