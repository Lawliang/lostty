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

    /// Reads a pane's visible text, bottom last. Claude's input box is the
    /// last line starting with `❯` right under a rule of `─`; a shell
    /// prompt ending in `❯` has no rule above it. It's empty when nothing
    /// follows the `❯` but a fresh session's `Try "…"` suggestion, and the
    /// line below is the box's closing rule. A spinner line just above the
    /// box (`✻ Stewing… (`) means Claude is working.
    static func input(in screen: String) -> Input {
        let lines = screen.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let row = lines.indices.last(where: { $0 > 0 && lines[$0].hasPrefix("❯") && isRule(lines[$0 - 1]) }) else {
            return .none
        }
        if lines[..<(row - 1)].suffix(3).contains(where: isSpinner) { return .none }
        let typed = lines[row].dropFirst().trimmingCharacters(in: .whitespaces)
        guard row + 1 < lines.count, isRule(lines[row + 1]) else { return .typed }
        return typed.isEmpty || typed.hasPrefix("Try \"") ? .empty : .typed
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
