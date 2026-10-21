#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffDirectiveTests {
    @Test func theLimitDirectiveCarriesTheNumbersAndTheFormat() {
        let text = ContextHandoffDirective.text(level: .limit, used: 312_400, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: nil, file: "/tmp/pane.handoff.md")
        #expect(text.contains("312k"))
        #expect(text.contains("300k"))
        #expect(text.contains("next clean break"))
        #expect(text.contains("<lostty-handoff>"))
        #expect(text.contains("## Active workflow"))
        #expect(text.count < 4_000)
    }

    @Test func theDirectiveNamesTheHandoffFile() {
        let text = ContextHandoffDirective.text(level: .limit, used: 312_400, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: nil, file: "/tmp/pane.handoff.md")
        #expect(text.contains("/tmp/pane.handoff.md"))
        #expect(text.contains("Write tool"))
    }

    @Test func theCeilingDirectiveSaysThisTurn() {
        let text = ContextHandoffDirective.text(level: .ceiling, used: 401_000, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: nil, file: "/tmp/pane.handoff.md")
        #expect(text.contains("end of this turn"))
        #expect(text.contains("400k"))
        #expect(text.count < 4_000)
    }

    @Test func theButtonDirectiveSaysTheUserAsked() {
        let text = ContextHandoffDirective.text(level: .limit, used: 150_000, limit: 300_000, ceiling: 400_000,
                                                byButton: true, problem: nil, file: "/tmp/pane.handoff.md")
        #expect(text.contains("The user asked"))
        #expect(!text.contains("300k"))
    }

    @Test func aProblemLeadsTheDirective() {
        let text = ContextHandoffDirective.text(level: .limit, used: 320_000, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: "Your handoff had no 'Active workflow'.", file: "/tmp/pane.handoff.md")
        #expect(text.hasPrefix("Lostty: Your handoff had no 'Active workflow'."))
    }

    @Test func theFreshStartFitsUnderClaudesCap() {
        let small = ContextHandoffDirective.freshStart(handoff: "## Goal\nX", path: "/h.md", used: 312_000)
        #expect(small.contains("/h.md"))
        #expect(small.contains("312k"))
        #expect(small.hasSuffix("## Goal\nX"))
        let big = ContextHandoffDirective.freshStart(handoff: String(repeating: "a", count: 12_000),
                                                     path: "/h.md", used: 312_000)
        #expect(big.count <= 9_000)
        #expect(big.contains("The full handoff is at /h.md. Read it before acting."))
    }

    @Test func continueLines() {
        #expect(ContextHandoffDirective.continueLine(.continueWork) == "Continue from the handoff.")
        #expect(ContextHandoffDirective.continueLine(.wait)
                == "Read the handoff, restate the open question word for word, and wait for me.")
    }

    @Test func thousands() {
        #expect(ContextHandoffDirective.k(312_999) == "312k")
        #expect(ContextHandoffDirective.k(999) == "0k")
    }

    @Test func restoreLinesOnlyWhenTheModelIsDropped() {
        #expect(ContextHandoffAgent.modelAlias("Opus 4.7 (1M context)") == "opus")
        #expect(ContextHandoffAgent.modelAlias("Sonnet") == "sonnet")
        #expect(ContextHandoffAgent.modelAlias("Mystery") == nil)
        #expect(ContextHandoffAgent.modelAlias(nil) == nil)
        let kept = ContextHandoffAgent.keepsModel
        defer { ContextHandoffAgent.keepsModel = kept }
        ContextHandoffAgent.keepsModel = true
        #expect(ContextHandoffAgent.restoreLines(model: "Opus") == [])
        ContextHandoffAgent.keepsModel = false
        #expect(ContextHandoffAgent.restoreLines(model: "Opus") == ["/model opus"])
        #expect(ContextHandoffAgent.restoreLines(model: "Mystery") == [])
    }
}
#endif
