#if os(macOS)
import Foundation
import Testing
@testable import Lostty

/// Screens laid out as tmux capture-pane showed real Claude Code 2.1 panes
/// (89 columns). Claude pads its prompt mark with a no-break space.
struct TicketDeliveryTests {
    private static let rule = String(repeating: "─", count: 89)
    private static let status = "  ⏵⏵ bypass permissions on (shift+tab to cycle)  ✔ Update installed · Restart to update"

    private func claude(above: [String] = ["⏺ Added the button and the callback."], box: [String]) -> String {
        (above + ["", Self.rule] + box + [Self.rule, Self.status, "", ""]).joined(separator: "\n")
    }

    @Test func anIdleClaudesEmptyBoxIsEmpty() {
        #expect(TicketDelivery.input(in: claude(box: ["❯\u{00A0}"])) == .empty)
        #expect(TicketDelivery.input(in: claude(above: ["✻ Cooked for 3m 26s · done Saturday 6:01 PM"], box: ["❯ "])) == .empty)
    }

    @Test func aFreshSessionsSuggestionCountsAsEmpty() {
        #expect(TicketDelivery.input(in: claude(above: ["╰───╯"], box: ["❯\u{00A0}Try \"refactor <filepath>\""])) == .empty)
    }

    @Test func halfAThoughtIsTyped() {
        #expect(TicketDelivery.input(in: claude(box: ["❯ ok, keep go"])) == .typed)
    }

    @Test func twoTypedLinesAreTyped() {
        #expect(TicketDelivery.input(in: claude(box: ["❯ first line", "  "])) == .typed)
        #expect(TicketDelivery.input(in: claude(box: ["❯ ", "  second line"])) == .typed)
    }

    @Test func aPermissionQuestionHidesTheBox() {
        let screen = [
            "⏺ Bash(rm -rf build)", "", Self.rule, " Bash command", "", "   rm -rf build", "",
            " Do you want to proceed?", " ❯ 1. Yes", "   2. No, and tell Claude what to do differently", "",
            " Esc to cancel",
        ].joined(separator: "\n")
        #expect(TicketDelivery.input(in: screen) == .none)
        let trust = ["", " ❯ No, exit", "   Yes, I trust this folder", "", " Enter to confirm · Esc to cancel"]
        #expect(TicketDelivery.input(in: trust.joined(separator: "\n")) == .none)
    }

    @Test func aShellPromptEndingInTheMarkIsNoBox() {
        let screen = ["~/projects/textberry main ❯", "❯ ", "~/projects/textberry ❯                    04:32:42 PM"]
        #expect(TicketDelivery.input(in: screen.joined(separator: "\n")) == .none)
        #expect(TicketDelivery.input(in: "") == .none)
    }

    @Test func aWorkingClaudeIsNoBoxToTypeInto() {
        let working = claude(above: ["     (ctrl+b ctrl+b (twice) to run in background)", "✻ Stewing… (4m 42s · ↓ 15.4k tokens)"],
                             box: ["❯\u{00A0}"])
        #expect(TicketDelivery.input(in: working) == .none)
    }

    @Test func thePromptIsTheTicketThenHowToReport() {
        var ticket = CanvasTicket(key: "TB-7", summary: "Add a \"Continue with Google\" button", details: "The OAuth callback at /auth/google.")
        #expect(TicketDelivery.prompt(for: ticket, feature: "Login") == """
            TB-7 · Login: Add a "Continue with Google" button

            The OAuth callback at /auth/google.

            When it's done, run: lostty +ticket review TB-7 "<one line on what changed>"
            If you can't go on, run: lostty +ticket blocked TB-7 "<why>"
            """)
        ticket.details = ""
        ticket.move(to: .review, by: .owner)
        ticket = TicketQueue.sendingBack("TB-7", note: "Use the brand blue", in: [ticket])?.first ?? ticket
        #expect(TicketDelivery.prompt(for: ticket, feature: "Login") == """
            TB-7 · Login: Add a "Continue with Google" button

            Sent back: Use the brand blue

            When it's done, run: lostty +ticket review TB-7 "<one line on what changed>"
            If you can't go on, run: lostty +ticket blocked TB-7 "<why>"
            """)
    }

    @Test func theTextActionKeepsNewlinesAndDropsEscapes() {
        #expect(TicketDelivery.textAction("a \"b\" \\ c\nd") == #"text:a \"b\" \\ c\nd"#)
        #expect(TicketDelivery.textAction("red \u{1B}[31mtext\u{07}\r\tend") == "text:red [31mtextend")
        #expect(TicketDelivery.textAction("TB-7 · Login") == "text:TB-7 · Login")
    }
}
#endif
