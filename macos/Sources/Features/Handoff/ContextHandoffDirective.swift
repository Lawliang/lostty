#if os(macOS)
import Foundation

/// What Lostty tells the agent (spec §1): the directive past the limit,
/// the fresh window's start, and the lines it types.
enum ContextHandoffDirective {
    /// The start text Claude keeps whole (its cap is 10,000).
    static let startMax = 9_000
    /// Of a longer handoff, how much the start text carries.
    static let startKeep = 7_500

    static let nudge = "Write your handoff file now: this window is at the Lostty context ceiling."

    /// "312k".
    static func k(_ tokens: Int) -> String { "\(tokens / 1_000)k" }

    /// `file`: where the agent writes its handoff (the store's
    /// `handoffFile`), so the reply the user reads stays short.
    static func text(level: ContextHandoffLevel, used: Int, limit: Int, ceiling: Int,
                     byButton: Bool, problem: String?, file: String) -> String {
        var lead: String
        if byButton {
            lead = "Lostty: The user asked for a handoff at the next clean break in this conversation."
        } else if level == .ceiling {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, at the \(k(ceiling)) ceiling set "
                + "in Lostty. Hand off at the end of this turn, even without a clean break: finish the step "
                + "you're on, then write a fuller handoff."
        } else {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, past the \(k(limit)) handoff "
                + "limit set in Lostty. Don't hand off now: keep working as usual, and plan to hand off at the "
                + "next clean break in the work. Until then, don't write the handoff or mention it."
        }
        if let problem { lead = "Lostty: \(problem) Write it again with every required section.\n\n" + lead }
        return lead + "\n\n" + practice(file: file)
    }

    private static func practice(file: String) -> String {
        """
        Clean breaks: a feature or plan task just finished and committed, tests green; you've done what the \
        user asked and are waiting on their answer or review; the working tree is clean, or holds only \
        changes you can describe in a sentence.
        Not a break: mid-debugging with hypotheses open; a half-made edit; tests failing for a reason you \
        don't yet understand; partway through reading code to understand something; a background job, build \
        or subagent still running; an ordinary progress update in the middle of the work.

        To hand off, and only then: as the last step of that turn, write the handoff with your Write tool to \
        this file (a new file; Lostty removes it once read):
        \(file)
        Under 8,000 characters; only what git and the files can't tell the next agent; no code dumps. These \
        sections:

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

        Then end the turn with a short, normal reply; don't repeat the handoff in it. When your turn ends, \
        Lostty reads the file, clears this window and starts a fresh one from it, so writing the file is the \
        handoff: never write it early or as a draft. Only if the file can't be written, end your reply with \
        the same sections between a <lostty-handoff> line and a </lostty-handoff> line instead. You don't \
        need to mention this message to the user.
        """
    }

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
