import Foundation

/// What comes before tmux on an attach, held back from the screen. The
/// phone's SSH library can only open a terminal by starting the login
/// shell, so each attach first shows sshd's "Last login" line and the
/// attach command echoed back, until tmux switches to the alternate screen
/// (`ESC[?1049h`, xterm-ghostty's smcup) and draws its own. Everything from
/// that switch on is shown; what came before is dropped. An attach that
/// ends before tmux takes over (`flush`) shows what was held, so its error
/// is still seen. Past `limit` held bytes something else is going on, and
/// they are shown rather than held further.
public struct AttachPreamble: Sendable {
    public static let takeover = Data("\u{1b}[?1049h".utf8)
    public static let limit = 64 * 1024

    private var held = Data()
    /// tmux took the screen (or the limit was hit): output passes through.
    public private(set) var passing = false

    public init() {}

    /// What of `data` to show now.
    public mutating func feed(_ data: Data) -> Data {
        if passing { return data }
        held.append(data)
        if let found = held.range(of: Self.takeover) {
            let shown = Data(held[found.lowerBound...])
            pass()
            return shown
        }
        if held.count > Self.limit {
            let shown = held
            pass()
            return shown
        }
        return Data()
    }

    /// The attach ended: whatever is still held, to show.
    public mutating func flush() -> Data {
        let shown = held
        pass()
        return shown
    }

    private mutating func pass() {
        held = Data()
        passing = true
    }
}
