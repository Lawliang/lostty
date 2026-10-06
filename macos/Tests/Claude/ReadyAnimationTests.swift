#if os(macOS)
import Testing
@testable import Ghostty

struct ReadyAnimationTests {
    let n = ReadyAnimation.text.count

    @Test func darkOverlayFadesInFirst() {
        let start = ReadyAnimation.frame(at: 0, reduceMotion: false)
        #expect(start.overlay == 0)
        #expect(start.prompt == 0)
        #expect(start.typed == 0)
        let faded = ReadyAnimation.frame(at: ReadyAnimation.overlayFade, reduceMotion: false)
        #expect(faded.overlay == 1)
        #expect(faded.prompt == 0)
    }

    @Test func thenThePromptFadesInWithTheCursorBeforeTyping() {
        let t = ReadyAnimation.overlayFade + ReadyAnimation.promptFade
        let frame = ReadyAnimation.frame(at: t, reduceMotion: false)
        #expect(frame.prompt == 1)
        #expect(frame.typed == 0)
        #expect(!frame.typing)
        // The cursor blinks beside the prompt while it waits.
        let a = ReadyAnimation.cursorOn(at: t + 0.01, reduceMotion: false)
        let b = ReadyAnimation.cursorOn(at: t + 0.01 + ReadyAnimation.blinkHalfPeriod, reduceMotion: false)
        #expect(a != b)
    }

    @Test func thenTheTextTypesQuicklyWithASolidCursor() {
        let mid = ReadyAnimation.typingStart + ReadyAnimation.perCharacter * 5.5
        let frame = ReadyAnimation.frame(at: mid, reduceMotion: false)
        #expect(frame.typed == 6)
        #expect(frame.typing)
        #expect(ReadyAnimation.cursorOn(at: mid, reduceMotion: false))
        // The whole line types in well under a second.
        #expect(ReadyAnimation.perCharacter * Double(n) < 0.8)
    }

    @Test func endsWithTheFullTextAndABlinkingCursor() {
        let end = ReadyAnimation.typingStart + ReadyAnimation.perCharacter * Double(n) + 0.01
        let frame = ReadyAnimation.frame(at: end, reduceMotion: false)
        #expect(frame.typed == n)
        #expect(!frame.typing)
        let later = end + 5
        #expect(ReadyAnimation.cursorOn(at: later, reduceMotion: false)
                != ReadyAnimation.cursorOn(at: later + ReadyAnimation.blinkHalfPeriod, reduceMotion: false))
    }

    @Test func settledFrameIsTheFinishedLine() {
        let frame = ReadyAnimation.settledFrame
        #expect(frame == ReadyAnimation.Frame(overlay: 1, prompt: 1, typed: n, typing: false))
    }

    @Test func reduceMotionShowsEverythingAtOnceWithASteadyCursor() {
        let frame = ReadyAnimation.frame(at: 0, reduceMotion: true)
        #expect(frame == ReadyAnimation.Frame(overlay: 1, prompt: 1, typed: n, typing: false))
        #expect(ReadyAnimation.cursorOn(at: 0.3, reduceMotion: true))
        #expect(ReadyAnimation.cursorOn(at: 0.9, reduceMotion: true))
    }
}
#endif
