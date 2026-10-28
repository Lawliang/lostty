#if os(macOS)
import AppKit
import GhosttyKit

/// Typing a ticket into its feature's agent (board spec §5): the prompt,
/// what a pane's screen says about Claude's input box, and the typing.
enum TicketDelivery {
    /// Claude Code's input box, as a pane's screen shows it.
    enum Input: Equatable {
        /// No input box Lostty may type into: a shell, a permission
        /// question (which hides the box), or Claude working.
        case none
        /// The box, with nothing typed in it.
        case empty
        /// The box, holding what someone typed.
        case typed
    }

    /// How long after the text Return goes: sent at once, Claude Code
    /// swallows it (measured in the board-typing prototype).
    static let enterDelay: TimeInterval = 0.3

    static func prompt(for ticket: CanvasTicket, feature: String) -> String {
        let key = ticket.key ?? ""
        let details = ticket.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (ticket.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "\(key) · \(feature): \(ticket.summary)",
            details,
            note.isEmpty ? "" : "Sent back: \(note)",
            "When it's done, run: lostty +ticket review \(key) \"<one line on what changed>\"\n"
                + "If you can't go on, run: lostty +ticket blocked \(key) \"<why>\"",
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// `text` as Ghostty's `text:` binding action, whose argument is a Zig
    /// string literal's body. Control characters but newline are dropped,
    /// so a ticket can't carry a terminal escape into the pane.
    static func textAction(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        let escaped = String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "text:" + escaped
    }

    /// Reads a pane's screen, bottom last, plain or with SGR escapes as
    /// tmux `capture-pane -e` writes it. Claude's input box is the last
    /// line starting with `❯` right under a rule of `─`; a shell prompt
    /// ending in `❯` has no rule above it. It's empty when nothing up to
    /// the box's closing rule follows the `❯` but faint text (the
    /// suggestion Claude shows after a turn) or a fresh session's
    /// `Try "…"`. A spinner line just above the box (`✻ Stewing… (`)
    /// means Claude is working.
    static func input(in screen: String) -> Input {
        let lines = Self.lines(of: screen)
        guard let row = lines.indices.last(where: {
            $0 > 0 && lines[$0].text.hasPrefix("❯") && isRule(lines[$0 - 1].text)
        }) else { return .none }
        if lines[..<(row - 1)].suffix(3).contains(where: { isSpinner($0.text) }) { return .none }
        guard let close = lines[(row + 1)...].firstIndex(where: { isRule($0.text) }) else { return .typed }
        let bright = lines[row].bright
        let typed = (bright.hasPrefix("❯") ? bright.dropFirst() : Substring(bright))
            .trimmingCharacters(in: .whitespaces)
        let below = lines[(row + 1)..<close].contains { !$0.bright.isEmpty }
        return !below && (typed.isEmpty || typed.hasPrefix("Try \"")) ? .empty : .typed
    }

    /// `screen`'s lines, trimmed, without escapes: all their text, and
    /// only the text not drawn faint (SGR 2 until 22 or a reset). Style
    /// carries over from one line to the next, as tmux writes it.
    private static func lines(of screen: String) -> [(text: String, bright: String)] {
        var lines: [(text: String, bright: String)] = [("", "")]
        var faint = false
        var rest = Substring(screen)
        while let char = rest.popFirst() {
            switch char {
            case "\n":
                lines.append(("", ""))
            case "\u{1B}" where rest.first == "[":
                rest = rest.dropFirst()
                let end = rest.firstIndex { $0.asciiValue.map { (0x40...0x7E).contains($0) } ?? false } ?? rest.endIndex
                if rest[end...].first == "m" { faint = isFaint(after: rest[..<end], was: faint) }
                rest = rest[end...].dropFirst()
            case "\u{1B}" where rest.first == "]":
                while let next = rest.popFirst(), next != "\u{07}" {
                    if next == "\u{1B}" { rest = rest.dropFirst(); break }
                }
            case "\u{1B}":
                rest = rest.dropFirst()
            default:
                lines[lines.count - 1].text.append(char)
                if !faint { lines[lines.count - 1].bright.append(char) }
            }
        }
        return lines.map { ($0.text.trimmingCharacters(in: .whitespaces), $0.bright.trimmingCharacters(in: .whitespaces)) }
    }

    private static func isFaint(after params: Substring, was faint: Bool) -> Bool {
        var faint = faint
        var codes = params.split(separator: ";", omittingEmptySubsequences: false).map { $0.isEmpty ? 0 : Int($0) ?? -1 }[...]
        while let code = codes.popFirst() {
            switch code {
            case 0, 22: faint = false
            case 2: faint = true
            case 38, 48, 58: codes = codes.dropFirst(codes.first == 5 ? 2 : 4)
            default: break
            }
        }
        return faint
    }

    private static func isRule(_ line: String) -> Bool {
        line.count >= 10 && line.allSatisfy { $0 == "─" }
    }

    private static func isSpinner(_ line: String) -> Bool {
        guard let first = line.first, "·✢✳✶✻✽*".contains(first) else { return false }
        return line.contains("…")
    }

    /// The pane's visible text now. Not `cachedVisibleContents`, which can
    /// be half a second old and miss a key just typed.
    @MainActor
    static func screen(of view: Ghostty.SurfaceView) -> String {
        guard let surface = view.surface else { return "" }
        let corner = { (coord: ghostty_point_coord_e) in
            ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: coord, x: 0, y: 0)
        }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: corner(GHOSTTY_POINT_COORD_TOP_LEFT), bottom_right: corner(GHOSTTY_POINT_COORD_BOTTOM_RIGHT),
            rectangle: false)
        guard ghostty_surface_read_text(surface, selection, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    /// The pane's screen with styles, from the tmux session `session`
    /// (an id) it shows, so a faint suggestion isn't taken for typed text.
    /// Its plain text when it shows none or tmux doesn't answer.
    @MainActor
    static func screen(of view: Ghostty.SurfaceView, session: String?) -> String {
        session.flatMap { TmuxClient(timeout: 0.5).run(["capture-pane", "-e", "-p", "-t", $0]) } ?? screen(of: view)
    }

    /// Types `text` into the pane as keys, not `sendText`'s bracketed
    /// paste, which Claude Code files as pasted content, then presses
    /// Return. False, and nothing typed, when the pane can't take it.
    @MainActor
    static func type(_ text: String, into view: Ghostty.SurfaceView) -> Bool {
        guard let model = view.surfaceModel, model.perform(action: textAction(text)) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + enterDelay) { [weak view] in
            MainActor.assumeIsolated {
                guard let model = view?.surfaceModel else { return }
                model.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press, mods: []))
                model.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .release, mods: []))
            }
        }
        return true
    }
}
#endif
