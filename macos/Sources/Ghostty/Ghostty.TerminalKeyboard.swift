import GhosttyKit

extension Ghostty.MobileInput {
    /// Lostty Mobile's own keyboard, as data: which keys sit where on each
    /// layer, how wide, and how Shift behaves. The view (TerminalKeyboard_UIKit)
    /// only draws this. Its return key makes a new line (`newline`); Send, in
    /// the strip under the keys where iOS puts the globe and mic, sends.
    enum Board {
        enum Layer: Equatable { case letters, numbers, symbols }

        enum Key: Equatable {
            /// Types this text (a letter in the case Shift says).
            case char(String)
            case shift
            case backspace
            /// Switches to that layer.
            case layer(Layer)
            case space
            /// A new line in the prompt, not sent.
            case newline
            /// Latches Ctrl for the next key (the same latch as the key
            /// row's), where iOS puts its emoji key.
            case ctrl
        }

        /// The return key's width; send, under it, is a little wider.
        static let returnWidth = 2.75
        /// 123 and ctrl.
        static let smallKeyWidth = 1.25

        /// One key and its width, in letter-key widths.
        struct Slot: Equatable {
            var key: Key
            var width: Double = 1
        }

        /// The rows of `layer`, top to bottom.
        static func rows(_ layer: Layer) -> [[Slot]] {
            func chars(_ s: String) -> [Slot] { s.map { Slot(key: .char(String($0))) } }
            func bottom(_ other: Layer) -> [Slot] {
                [Slot(key: .layer(other), width: smallKeyWidth), Slot(key: .ctrl, width: smallKeyWidth),
                 Slot(key: .space, width: 4.75), Slot(key: .newline, width: returnWidth)]
            }
            switch layer {
            case .letters:
                return [
                    chars("qwertyuiop"),
                    chars("asdfghjkl"),
                    [Slot(key: .shift, width: 1.5)] + chars("zxcvbnm") + [Slot(key: .backspace, width: 1.5)],
                    bottom(.numbers),
                ]
            case .numbers:
                return [
                    chars("1234567890"),
                    chars("-/:;()$&@\""),
                    [Slot(key: .layer(.symbols), width: 1.5)] + punctuation + [Slot(key: .backspace, width: 1.5)],
                    bottom(.letters),
                ]
            case .symbols:
                return [
                    chars("[]{}#%^*+="),
                    // The terminal's own: _ \ | ~ < > `.
                    chars("_\\|~<>`€£•"),
                    [Slot(key: .layer(.numbers), width: 1.5)] + punctuation + [Slot(key: .backspace, width: 1.5)],
                    bottom(.letters),
                ]
            }
        }

        private static let punctuation: [Slot] = ".,?!'".map { Slot(key: .char(String($0)), width: 1.4) }

        /// What a key that switches to `layer` says.
        static func label(_ layer: Layer) -> String {
            switch layer {
            case .letters: "ABC"
            case .numbers: "123"
            case .symbols: "#+="
            }
        }

        /// A swipe across the keyboard: an arrow key.
        enum Swipe: Equatable, CaseIterable {
            case up, down, left, right

            /// Travelled at least this far (points), a drag is a swipe.
            static let minDistance: Double = 30

            /// The swipe a drag of (`dx`, `dy`) makes: its longer axis, once
            /// far enough; nil for a short or perfectly diagonal drag.
            static func of(dx: Double, dy: Double) -> Swipe? {
                guard max(abs(dx), abs(dy)) >= minDistance, abs(dx) != abs(dy) else { return nil }
                if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
                return dy > 0 ? .down : .up
            }

            /// The arrow key it presses.
            func press(ctrl: Bool) -> Ghostty.MobileInput.Press {
                let key: Ghostty.MobileInput.Key = switch self {
                case .up: .arrowUp
                case .down: .arrowDown
                case .left: .arrowLeft
                case .right: .arrowRight
                }
                return Ghostty.MobileInput.Press(key: key, mods: ctrl ? .ctrl : [])
            }

            /// The SF Symbol its feedback shows.
            var symbol: String {
                switch self {
                case .up: "arrow.up"
                case .down: "arrow.down"
                case .left: "arrow.left"
                case .right: "arrow.right"
                }
            }

            /// Unit direction, y down.
            var vector: (dx: Double, dy: Double) {
                switch self {
                case .up: (0, -1)
                case .down: (0, 1)
                case .left: (-1, 0)
                case .right: (1, 0)
                }
            }
        }

        /// Shift: a tap capitalizes the next letter, a double tap locks caps
        /// until tapped again.
        enum Shift: Equatable {
            case off, once, locked

            /// Shift tapped; `double` when it closely follows the last tap.
            mutating func tapped(double: Bool) {
                switch self {
                case .off: self = .once
                case .once: self = double ? .locked : .off
                case .locked: self = .off
                }
            }

            /// A letter was typed: a single shift is used up.
            mutating func typedLetter() {
                if self == .once { self = .off }
            }

            var isUpper: Bool { self != .off }
        }

        /// What a character key types under `shift`.
        static func text(_ char: String, shift: Shift) -> String {
            shift.isUpper ? char.uppercased() : char
        }
    }
}
