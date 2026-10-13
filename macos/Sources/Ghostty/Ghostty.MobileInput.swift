import GhosttyKit

extension Ghostty {
    /// Lostty Mobile: turns phone input — soft-keyboard text, the key row and
    /// a sticky Ctrl — into key presses for `ghostty_surface_key`, so the
    /// core's encoder still applies the terminal's modes (application cursor
    /// keys, the kitty keyboard protocol). Compiled for iOS, and unit-tested from the macOS
    /// target (which compiles it too).
    enum MobileInput {
        /// The keys a phone press can name. Keycodes are the macOS virtual
        /// keycodes that `Ghostty.Input.Key.keyCode` uses, so the core maps
        /// them the same on both platforms.
        enum Key: CaseIterable, Equatable {
            case a, b, c, d, e, f, g, h, i, j, k, l, m
            case n, o, p, q, r, s, t, u, v, w, x, y, z
            case digit0, digit1, digit2, digit3, digit4
            case digit5, digit6, digit7, digit8, digit9
            case space, enter, tab, escape, backspace
            case arrowLeft, arrowDown, arrowUp, arrowRight

            var keycode: UInt32 {
                switch self {
                case .a: 0x00
                case .b: 0x0b
                case .c: 0x08
                case .d: 0x02
                case .e: 0x0e
                case .f: 0x03
                case .g: 0x05
                case .h: 0x04
                case .i: 0x22
                case .j: 0x26
                case .k: 0x28
                case .l: 0x25
                case .m: 0x2e
                case .n: 0x2d
                case .o: 0x1f
                case .p: 0x23
                case .q: 0x0c
                case .r: 0x0f
                case .s: 0x01
                case .t: 0x11
                case .u: 0x20
                case .v: 0x09
                case .w: 0x0d
                case .x: 0x07
                case .y: 0x10
                case .z: 0x06
                case .digit0: 0x1d
                case .digit1: 0x12
                case .digit2: 0x13
                case .digit3: 0x14
                case .digit4: 0x15
                case .digit5: 0x17
                case .digit6: 0x16
                case .digit7: 0x1a
                case .digit8: 0x1c
                case .digit9: 0x19
                case .space: 0x31
                case .enter: 0x24
                case .tab: 0x30
                case .escape: 0x35
                case .backspace: 0x33
                case .arrowLeft: 0x7b
                case .arrowDown: 0x7d
                case .arrowUp: 0x7e
                case .arrowRight: 0x7c
                }
            }
        }

        /// Modifier bits, mirroring `ghostty_input_mods_e`.
        struct Mods: OptionSet, Equatable {
            let rawValue: UInt32

            static let shift = Mods(rawValue: GHOSTTY_MODS_SHIFT.rawValue)
            static let ctrl = Mods(rawValue: GHOSTTY_MODS_CTRL.rawValue)

            var cMods: ghostty_input_mods_e {
                ghostty_input_mods_e(rawValue)
            }
        }

        /// One key press.
        struct Press: Equatable {
            /// nil: a character with no key of its own (punctuation, emoji).
            var key: Key?
            var mods: Mods = []
            /// The text the key produces; nil when Ctrl is held, so the
            /// encoder sends the control code for `unshifted`.
            var text: String?
            var unshifted: UInt32 = 0

            /// A keycode no keyboard uses: the core treats the press as an
            /// unidentified key and sends its text.
            static let noKeycode: UInt32 = 0xFFFF

            func withCValue<T>(action: ghostty_input_action_e, _ body: (ghostty_input_key_s) -> T) -> T {
                var event = ghostty_input_key_s()
                event.action = action
                event.keycode = key?.keycode ?? Self.noKeycode
                event.mods = mods.cMods
                event.consumed_mods = Mods().cMods
                event.unshifted_codepoint = unshifted
                event.composing = false
                guard let text else {
                    event.text = nil
                    return body(event)
                }
                return text.withCString { ptr in
                    event.text = ptr
                    return body(event)
                }
            }
        }

        /// Keys outside the letters: esc and the keyboard switch, on Lostty's
        /// keyboard and in the row over iOS's.
        enum RowKey: String, CaseIterable, Identifiable {
            case esc, keyboard

            var id: String { rawValue }

            /// The SF Symbol a key shows instead of its label.
            var symbol: String? {
                switch self {
                case .keyboard: "globe"
                case .esc: nil
                }
            }

            var accessibilityName: String {
                switch self {
                case .esc: "Escape"
                case .keyboard: "Switch keyboard"
                }
            }

            var label: String {
                switch self {
                case .esc: "esc"
                case .keyboard: "🌐"
                }
            }
        }

        static let backspace = Press(key: .backspace)

        /// A new line that isn't sent: Ctrl+J, a line feed, which Claude
        /// Code (and most line editors) insert as a new line. Lostty's
        /// keyboard's return key.
        static let newline = Press(key: .j, mods: .ctrl, text: nil, unshifted: 0x6A)

        /// Enter: sends what's typed. Lostty's keyboard's Send.
        static let enter = Press(key: .enter)

        /// Presses for text the soft keyboard inserted. `ctrl` (the sticky
        /// key) applies to the first character only.
        static func presses(typed text: String, ctrl: Bool) -> [Press] {
            text.enumerated().map { index, character in
                press(for: character, ctrl: ctrl && index == 0)
            }
        }

        /// The press for a key-row key; nil for the keyboard switch, which
        /// sends nothing.
        static func press(for key: RowKey, ctrl: Bool) -> Press? {
            let mods: Mods = ctrl ? .ctrl : []
            switch key {
            case .keyboard: return nil
            case .esc: return Press(key: .escape, mods: mods)
            }
        }

        private static let letterKeys: [Character: Key] = Dictionary(uniqueKeysWithValues: zip(
            "abcdefghijklmnopqrstuvwxyz",
            [Key.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z]))

        private static let digitKeys: [Character: Key] = Dictionary(uniqueKeysWithValues: zip(
            "0123456789",
            [Key.digit0, .digit1, .digit2, .digit3, .digit4,
             .digit5, .digit6, .digit7, .digit8, .digit9]))

        private static func press(for character: Character, ctrl: Bool) -> Press {
            let ctrlMods: Mods = ctrl ? .ctrl : []
            if character == "\n" || character == "\r" { return Press(key: .enter, mods: ctrlMods) }
            if character == "\t" { return Press(key: .tab, mods: ctrlMods) }

            let lower = Character(character.lowercased())
            if let key = letterKeys[lower], let scalar = lower.unicodeScalars.first {
                // Ctrl+letter is a control code: shift is dropped.
                let shifted: Mods = (character == lower || ctrl) ? [] : .shift
                return Press(
                    key: key,
                    mods: ctrlMods.union(shifted),
                    text: ctrl ? nil : String(character),
                    unshifted: scalar.value)
            }
            if let key = digitKeys[character] ?? (character == " " ? .space : nil),
               let scalar = character.unicodeScalars.first {
                return Press(key: key, mods: ctrlMods, text: ctrl ? nil : String(character), unshifted: scalar.value)
            }

            // Everything else is text: punctuation, accents, emoji.
            let scalars = character.unicodeScalars
            return Press(key: nil, text: String(character), unshifted: scalars.count == 1 ? scalars.first!.value : 0)
        }
    }
}
