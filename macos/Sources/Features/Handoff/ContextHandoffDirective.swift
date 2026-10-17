#if os(macOS)
import Foundation

/// What Lostty tells the agent (spec §1): the directive past the limit,
/// the fresh window's start, and the lines it types.
enum ContextHandoffDirective {
    /// The start text Claude keeps whole (its cap is 10,000).
    static let startMax = 9_000
    /// Of a longer handoff, how much the start text carries.
    static let startKeep = 7_500

    static let nudge = "Write your handoff now: this window is at the Lostty context ceiling."

    /// "312k".
    static func k(_ tokens: Int) -> String { "\(tokens / 1_000)k" }

    static func text(level: ContextHandoffLevel, used: Int, limit: Int, ceiling: Int,
                     byButton: Bool, problem: String?) -> String {
        var lead: String
        if byButton {
            lead = "Lostty: The user asked for a handoff at the next clean break in this conversation."
        } else if level == .ceiling {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, at the \(k(ceiling)) ceiling set "
                + "in Lostty. Hand off at the end of this turn, even without a clean break: finish the step "
                + "you're on, then write a fuller handoff."
        } else {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, past the \(k(limit)) handoff "
                + "limit set in Lostty. Keep working, and hand off at the next clean break in the work. Don't "
                + "stop early to do it."
        }
        if let problem { lead = "Lostty: \(problem) Write it again with every required section.\n\n" + lead }
        return lead + "\n\n" + practice
    }

    private static let practice = """
    Clean breaks: a feature or plan task just finished and committed, tests green; you just asked the user \
    a question or handed something back; the working tree is clean, or holds only changes you can describe \
    in a sentence.
    Not a break: mid-debugging with hypotheses open; a half-made edit; tests failing for a reason you don't \
    yet understand; partway through reading code to understand something; a background job, build or \
    subagent still running.

    To hand off, end your turn with this block as the last thing in your reply. Under 8,000 characters; \
    only what git and the files can't tell the next agent; no code dumps.

    <lostty-handoff>
    ## Goal
    (what we're building and why, 2-3 sentences)
    ## Where we are
    (done, with commits; in progress; the exact next step)
    ## Decisions
    (rulings made and options ruled out, with why)
    ## Your instructions
    (the user's instructions from this conversation)
    ## Open threads
    (questions waiting on the user, word for word; hand tests pending)
    ## Gotchas
    (traps found: sandbox refusals, flaky tests, wrong paths)
    ## Pointers
    (branch, worktree, spec, plan, key files)
    ## Active workflow
    (the skill or process you're following and where it stands, or "none")
    ## Next
    continue (or "wait" if you're waiting on the user)
    </lostty-handoff>

    Lostty then clears this window and starts a fresh one from your handoff. You don't need to mention \
    this message to the user.
    """

    /// What the start hook gives the fresh window.
    static func freshStart(handoff: String, path: String, used: Int) -> String {
        let lead = "Lostty: you're continuing from a handoff Lostty saved at \(path) when the last window "
            + "reached \(k(used)) tokens. First re-enter the Active workflow it names (invoke that skill again, "
            + "read its ledger). Check the branch and `git status` against the handoff before acting. If "
            + "anything disagrees, say so and wait.\n\n"
        let whole = lead + handoff
        guard whole.count > startMax else { return whole }
        return lead + String(handoff.prefix(startKeep))
            + "\n\n(The full handoff is at \(path). Read it before acting.)"
    }

    static func continueLine(_ next: ContextHandoff.Next) -> String {
        switch next {
        case .continueWork: "Continue from the handoff."
        case .wait: "Read the handoff, restate the open question word for word, and wait for me."
        }
    }
}
#endif
