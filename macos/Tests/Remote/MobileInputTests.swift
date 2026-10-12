import GhosttyKit
import Testing
@testable import Ghostty

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
        #expect(MI.press(for: .tab, ctrl: false) == P(key: .tab, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .shiftTab, ctrl: false) == P(key: .tab, mods: .shift, text: nil, unshifted: 0))
        #expect(MI.press(for: .up, ctrl: false) == P(key: .arrowUp, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .left, ctrl: true) == P(key: .arrowLeft, mods: .ctrl, text: nil, unshifted: 0))
        #expect(MI.press(for: .slash, ctrl: false) == P(key: nil, mods: [], text: "/", unshifted: 0x2F))
        #expect(MI.press(for: .at, ctrl: false) == P(key: nil, mods: [], text: "@", unshifted: 0x40))
        #expect(MI.press(for: .ctrl, ctrl: false) == nil)
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
        for key in MI.RowKey.allCases { #expect(!key.label.isEmpty) }
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
}
