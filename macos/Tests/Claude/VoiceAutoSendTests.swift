#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct VoiceAutoSendTests {
    private let rule = String(repeating: "─", count: 40)
    private let footer = "  ⏵⏵ bypass permissions on (shift+tab to cycle)        ⏺ REC · tap to send"

    @Test func readsTheBarAndWordsWhileRecording() {
        let screen = [" ▐▛███▛█   Claude Code", rule, "❯ ▃", rule, footer].joined(separator: "\n")
        #expect(VoiceFrame.parse(screen) == VoiceFrame(words: "", level: 3))
        let talking = [rule, "❯ fix the menu bar so", "  it opens ▅", rule, footer].joined(separator: "\n")
        #expect(VoiceFrame.parse(talking) == VoiceFrame(words: "fix the menu bar so it opens", level: 5))
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
        #expect(watch.sendsAt == start + 5.5)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 4) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 5) == .wait)
        #expect(watch.update(VoiceFrame(words: "Just testing"), now: start + 5.5) == .send)
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

    @Test func maybeSpeechNearTheEndPutsTheSendOff() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 2), now: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 2), now: start + 1)
        #expect(watch.sendsAt == start + 4)
        // You start again just before it sends: the bar jumps before any word lands.
        #expect(watch.update(VoiceFrame(words: "fix it", level: 5), now: start + 3.9) == .wait)
        #expect(watch.update(VoiceFrame(words: "fix it", level: 2), now: start + 4.5) == .wait)
        // Its words arrive in time, and nothing sends.
        _ = watch.update(VoiceFrame(words: "fix it and also", level: 3), now: start + 5)
        #expect(watch.sendsAt == nil)
    }

    @Test func roomNoiseDoesntPutTheSendOff() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 3), now: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 2), now: start + 1)
        #expect(watch.update(VoiceFrame(words: "fix it", level: 3), now: start + 3) == .wait)
        #expect(watch.update(VoiceFrame(words: "fix it", level: 2), now: start + 4) == .send)
    }

    @Test func aNoiseWithNoWordsStillSendsAfterListening() {
        let start = Date()
        var watch = VoiceWatch(since: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 1), now: start)
        _ = watch.update(VoiceFrame(words: "fix it", level: 1), now: start + 1)
        _ = watch.update(VoiceFrame(words: "fix it", level: 6), now: start + 3.5)
        #expect(watch.update(VoiceFrame(words: "fix it", level: 1), now: start + 5) == .wait)
        #expect(watch.update(VoiceFrame(words: "fix it", level: 1), now: start + 5.5) == .send)
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
