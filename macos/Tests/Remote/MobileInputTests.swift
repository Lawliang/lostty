import GhosttyKit
import Testing
@testable import Lostty

private typealias MI = Ghostty.MobileInput
private typealias P = Ghostty.MobileInput.Press

struct MobileInputTests {
    @Test func lowercaseLetterIsItsKeyWithText() {
        #expect(MI.presses(typed: "a", ctrl: false) == [P(key: .a, mods: [], text: "a", unshifted: 0x61)])
    }

    @Test func uppercaseLetterIsShiftedWithItsText() {
        #expect(MI.presses(typed: "Q", ctrl: false) == [P(key: .q, mods: .shift, text: "Q", unshifted: 0x71)])
    }

    @Test func ctrlLetterHasNoTextSoTheEncoderSendsAControlCode() {
        #expect(MI.presses(typed: "c", ctrl: true) == [P(key: .c, mods: .ctrl, text: nil, unshifted: 0x63)])
    }

    @Test func ctrlWithAnUppercaseLetterDropsShift() {
        #expect(MI.presses(typed: "C", ctrl: true) == [P(key: .c, mods: .ctrl, text: nil, unshifted: 0x63)])
    }

    @Test func ctrlAppliesToTheFirstCharacterOnly() {
        #expect(MI.presses(typed: "cd", ctrl: true) == [
            P(key: .c, mods: .ctrl, text: nil, unshifted: 0x63),
            P(key: .d, mods: [], text: "d", unshifted: 0x64),
        ])
    }

    @Test func digitsSpaceAndReturn() {
        #expect(MI.presses(typed: "1 \n", ctrl: false) == [
            P(key: .digit1, mods: [], text: "1", unshifted: 0x31),
            P(key: .space, mods: [], text: " ", unshifted: 0x20),
            P(key: .enter, mods: [], text: nil, unshifted: 0),
        ])
    }

    @Test func punctuationAndEmojiAreTextWithNoKey() {
        #expect(MI.presses(typed: "/", ctrl: false) == [P(key: nil, mods: [], text: "/", unshifted: 0x2F)])
        #expect(MI.presses(typed: "👍", ctrl: false) == [P(key: nil, mods: [], text: "👍", unshifted: 0x1F44D)])
        // A character made of several scalars (flag) keeps its text whole.
        #expect(MI.presses(typed: "🇯🇵", ctrl: false) == [P(key: nil, mods: [], text: "🇯🇵", unshifted: 0)])
    }

    @Test func keyRowKeys() {
        #expect(MI.press(for: .esc, ctrl: false) == P(key: .escape, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .esc, ctrl: true) == P(key: .escape, mods: .ctrl, text: nil, unshifted: 0))
        // The globe switches keyboards; it types nothing.
        #expect(MI.press(for: .keyboard, ctrl: false) == nil)
    }

    @Test func backspace() {
        #expect(MI.backspace == P(key: .backspace, mods: [], text: nil, unshifted: 0))
    }

    @Test func cValueUsesTheKeysKeycodeOrNone() {
        let a = P(key: .a, mods: .ctrl, text: nil, unshifted: 0x61)
        a.withCValue(action: GHOSTTY_ACTION_PRESS) { c in
            #expect(c.keycode == MI.Key.a.keycode)
            #expect(c.mods == MI.Mods.ctrl.cMods)
            #expect(c.text == nil)
            #expect(c.unshifted_codepoint == 0x61)
        }
        let slash = P(key: nil, mods: [], text: "/", unshifted: 0x2F)
        slash.withCValue(action: GHOSTTY_ACTION_PRESS) { c in
            #expect(c.keycode == P.noKeycode)
            #expect(String(cString: c.text!) == "/")
        }
    }

    @Test func everyRowKeyHasALabel() {
        for key in MI.RowKey.allCases {
            #expect(!key.label.isEmpty)
            #expect(!key.accessibilityName.isEmpty)
        }
    }

    @Test func newlineIsCtrlJAndEnterSends() {
        // Lostty's keyboard: return is a line feed, Send is Enter.
        #expect(MI.newline == P(key: .j, mods: .ctrl, text: nil, unshifted: 0x6A))
        #expect([MI.newline] == MI.presses(typed: "j", ctrl: true))
        #expect(MI.enter == P(key: .enter, mods: [], text: nil, unshifted: 0))
        // The iOS keyboard's return is still Enter.
        #expect(MI.presses(typed: "\n", ctrl: false) == [MI.enter])
    }

    @Test func theRowHasOnlyWhatTheKeyboardLacks() {
        #expect(MI.RowKey.allCases == [.esc, .keyboard])
        #expect(MI.RowKey.allCases.filter { $0.symbol != nil } == [.keyboard])
    }

    /// The keycodes are copied from the desktop table; this keeps them in step.
    @Test func keycodesMatchTheDesktopTable() {
        let desktop: [MI.Key: Ghostty.Input.Key] = [
            .a: .a, .b: .b, .c: .c, .d: .d, .e: .e, .f: .f, .g: .g, .h: .h, .i: .i,
            .j: .j, .k: .k, .l: .l, .m: .m, .n: .n, .o: .o, .p: .p, .q: .q, .r: .r,
            .s: .s, .t: .t, .u: .u, .v: .v, .w: .w, .x: .x, .y: .y, .z: .z,
            .digit0: .digit0, .digit1: .digit1, .digit2: .digit2, .digit3: .digit3,
            .digit4: .digit4, .digit5: .digit5, .digit6: .digit6, .digit7: .digit7,
            .digit8: .digit8, .digit9: .digit9,
            .space: .space, .enter: .enter, .tab: .tab, .escape: .escape,
            .backspace: .backspace, .arrowLeft: .arrowLeft, .arrowDown: .arrowDown,
            .arrowUp: .arrowUp, .arrowRight: .arrowRight,
        ]
        #expect(desktop.count == MI.Key.allCases.count)
        for key in MI.Key.allCases {
            #expect(key.keycode == UInt32(desktop[key]!.keyCode!), "\(key)")
        }
    }

    @Test func everyLayerHasFourRowsTenKeysWide() {
        for layer in [MI.Board.Layer.letters, .numbers, .symbols] {
            let rows = MI.Board.rows(layer)
            #expect(rows.count == 4)
            // Rows fill the width (the letters' middle row is inset by half
            // a key each side, as on iOS).
            for (i, row) in rows.enumerated() where !(layer == .letters && i == 1) {
                #expect(abs(row.map(\.width).reduce(0, +) - 10) < 0.001, "\(layer) row \(i)")
            }
            #expect(rows[3].map(\.key).contains(.newline))
            // Ctrl right of the layer key, where iOS has emoji.
            #expect(rows[3][1].key == .ctrl)
            #expect(rows[3].map(\.key).contains(.space))
        }
        #expect(MI.Board.rows(.letters)[0].map(\.key) == "qwertyuiop".map { .char(String($0)) })
    }

    @Test func theTerminalsSymbolsAreOnTheKeyboard() {
        let typed = Set([MI.Board.Layer.letters, .numbers, .symbols].flatMap { layer in
            MI.Board.rows(layer).flatMap { $0 }.compactMap { slot -> String? in
                if case .char(let c) = slot.key { return c }
                return nil
            }
        })
        for char in ["|", "\\", "~", "`", "<", ">", "_", "-", "/", "$", "&", "*", "\"", "'", "@", "#", "!"] {
            #expect(typed.contains(char), "\(char)")
        }
    }

    @Test func shiftCapitalizesOnceOrLocks() {
        var shift = MI.Board.Shift.off
        shift.tapped(double: false)
        #expect(shift == .once)
        #expect(MI.Board.text("a", shift: shift) == "A")
        shift.typedLetter()
        #expect(shift == .off)
        #expect(MI.Board.text("a", shift: shift) == "a")
        // Double tap: caps lock, kept across letters until tapped again.
        shift.tapped(double: false)
        shift.tapped(double: true)
        #expect(shift == .locked)
        shift.typedLetter()
        #expect(shift == .locked)
        shift.tapped(double: false)
        #expect(shift == .off)
    }

    // MARK: Swipes (paths from a real keyboard log, in points from the start)

    fileprivate typealias Track = MI.Board.SwipeTrack

    /// The drag through `path`; the arrow it makes when the finger lifts at its last point.
    fileprivate func swipe(_ path: [(Double, Double)]) -> (track: Track, arrow: MI.Board.Swipe?) {
        var track = Track()
        for (dx, dy) in path.dropLast() { track.move(dx: dx, dy: dy) }
        let last = path.last ?? (0, 0)
        let arrow = track.end(dx: last.0, dy: last.1)
        return (track, arrow)
    }

    @Test func dragsWhileTypingNeverBecomeSwipes() {
        // 0.07 s and 0.12 s after a key press, peaking at 27 and 25 pt.
        for path in [[(-11.0, 22.0), (-5, 27)], [(-23.0, 5.0), (-25, 7)]] {
            let (track, arrow) = swipe(path)
            #expect(track.phase == .undecided)
            #expect(arrow == nil)
        }
    }

    @Test func aClearSwipeMakesItsArrow() {
        #expect(swipe([(0, -27), (10, -60), (30, -120), (46, -195)]).arrow == .up)
        #expect(swipe([(3, 28), (10, 60), (37, 120)]).arrow == .down)
        #expect(swipe([(-40, 2), (-90, 10)]).arrow == .left)
        #expect(swipe([(40, -3), (80, 12)]).arrow == .right)
    }

    @Test func itLocksTheWayItWasGoingOncePast32() {
        var track = Track()
        track.move(dx: 0, dy: -31)
        #expect(track.phase == .undecided)
        track.move(dx: 2, dy: -33)
        #expect(track.phase == .going(.up))
    }

    @Test func turningBackCancelsIt() {
        // Up about 150 pt, then back down and off to the right: no arrow at
        // all, rather than the right arrow the old rule made.
        let (track, arrow) = swipe([(-2, -40), (-5, -90), (0, -149), (20, -60), (36, -16)])
        #expect(track.phase == .confused)
        #expect(arrow == nil)
    }

    @Test func wanderingOffSidewaysCancelsIt() {
        let (track, arrow) = swipe([(0, -40), (30, -45), (60, -48)])
        #expect(track.phase == .confused)
        #expect(arrow == nil)
    }

    @Test func aSmallWobbleIsStillASwipe() {
        #expect(swipe([(0, -40), (0, -80), (4, -70), (6, -90)]).arrow == .up)
    }

    @Test func pastThe32ButShortOf40MakesNoArrow() {
        let (track, arrow) = swipe([(0, -33), (0, -38)])
        #expect(track.phase == .going(.up))
        #expect(arrow == nil)
    }

    @Test func aPerfectlyDiagonalDragWaitsToTellWhich() {
        var track = Track()
        track.move(dx: 30, dy: 30)
        #expect(track.phase == .undecided)
        track.move(dx: 30, dy: 45)
        #expect(track.phase == .going(.down))
    }

    @Test func aSwipePressesItsArrowWithCtrlIfLatched() {
        #expect(MI.Board.Swipe.up.press(ctrl: false) == P(key: .arrowUp, mods: [], text: nil, unshifted: 0))
        #expect(MI.Board.Swipe.left.press(ctrl: true) == P(key: .arrowLeft, mods: .ctrl, text: nil, unshifted: 0))
        #expect(MI.Board.Swipe.allCases.map { $0.press(ctrl: false).key } == [.arrowUp, .arrowDown, .arrowLeft, .arrowRight])
    }
}
