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

            /// Travelled at least this far (points) its way, a swipe makes
            /// its arrow (`SwipeTrack`).
            static let minDistance: Double = 40

            /// Which way a drag of (`dx`, `dy`) mostly goes; nil when
            /// perfectly diagonal.
            static func way(dx: Double, dy: Double) -> Swipe? {
                guard abs(dx) != abs(dy) else { return nil }
                if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
                return dy > 0 ? .down : .up
            }

            /// How far (`dx`, `dy`) has gone this way, and how far off to the side.
            func along(dx: Double, dy: Double) -> Double {
                switch self {
                case .up: -dy
                case .down: dy
                case .left: -dx
                case .right: dx
                }
            }

            func across(dx: Double, dy: Double) -> Double {
                switch self {
                case .up, .down: abs(dx)
                case .left, .right: abs(dy)
                }
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

        /// One finger's drag across the keyboard, judged as it goes. A tap
        /// that wanders a little stays a tap: it only becomes a swipe past
        /// `startDistance` (taps in a real log drifted under 24 pt; drags
        /// while typing fast, up to 27). Then the way it was going is locked
        /// in, and turning back or wandering off sideways gives it up: a
        /// confusing drag types nothing rather than a surprising arrow.
        struct SwipeTrack: Equatable {
            enum Phase: Equatable {
                case undecided
                case going(Swipe)
                /// Turned back or wandered off: no arrow, whatever follows.
                case confused
            }

            static let startDistance: Double = 32
            /// Coming back this share of the way travelled (at least
            /// `minBacktrack`) is turning back.
            static let backtrackShare: Double = 1.0 / 3
            static let minBacktrack: Double = 16

            private(set) var phase: Phase = .undecided
            /// The furthest it got its way.
            private var peak: Double = 0

            init() {}

            /// The finger is now (`dx`, `dy`) from where it touched down.
            mutating func move(dx: Double, dy: Double) {
                switch phase {
                case .confused:
                    return
                case .undecided:
                    guard (dx * dx + dy * dy).squareRoot() >= Self.startDistance, let way = Swipe.way(dx: dx, dy: dy) else { return }
                    phase = .going(way)
                    peak = way.along(dx: dx, dy: dy)
                case .going(let way):
                    let progress = way.along(dx: dx, dy: dy)
                    peak = max(peak, progress)
                    let turnedBack = peak - progress > max(Self.minBacktrack, peak * Self.backtrackShare)
                    let wandered = way.across(dx: dx, dy: dy) > progress
                    if turnedBack || wandered { phase = .confused }
                }
            }

            /// The arrow, once the finger lifts at (`dx`, `dy`): its locked
            /// way, if it went at least `Swipe.minDistance` that way.
            mutating func end(dx: Double, dy: Double) -> Swipe? {
                move(dx: dx, dy: dy)
                guard case .going(let way) = phase, way.along(dx: dx, dy: dy) >= Swipe.minDistance else { return nil }
                return way
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
