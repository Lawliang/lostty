#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ContextHandoffExtractTests {
    func block(next: String = "continue", workflow: String? = "none", threads: String? = nil) -> String {
        var lines = ["<lostty-handoff>", "## Goal", "Quit item in the menu bar.",
                     "## Where we are", "Quit committed as c52b00ef5; next: tests.", ""]
        if let threads { lines += ["## Open threads", threads] }
        if let workflow { lines += ["## Active workflow", workflow] }
        lines += ["## Next", next, "</lostty-handoff>"]
        return lines.joined(separator: "\n")
    }

    @Test func aValidBlockAtTheEndOfTheReply() throws {
        let found = try ContextHandoffExtract.find(in: "All done.\n\n" + block()).get()
        #expect(found.next == .continueWork)
        #expect(found.summary == "Quit committed as c52b00ef5; next: tests.")
        #expect(found.text.hasPrefix("## Goal"))
        #expect(!found.text.contains("lostty-handoff"))
    }

    @Test func noBlockIsNone() {
        #expect(ContextHandoffExtract.find(in: "Just a reply.") == .failure(.none))
    }

    @Test func aBlockInsideACodeFenceIsNotAHandoff() {
        let reply = "The format is:\n```\n" + block() + "\n```\nThat's it."
        #expect(ContextHandoffExtract.find(in: reply) == .failure(.none))
    }

    @Test func theLastOfTwoBlocksWins() throws {
        let reply = block(next: "wait", threads: "Merge now?") + "\n\n" + block(next: "continue")
        #expect(try ContextHandoffExtract.find(in: reply).get().next == .continueWork)
    }

    @Test func aMissingActiveWorkflowIsNamed() {
        #expect(ContextHandoffExtract.find(in: block(workflow: nil)) == .failure(.missing("Active workflow")))
    }

    @Test func aMissingNextMeansWaitAndNeedsOpenThreads() throws {
        let noNext = block().replacingOccurrences(of: "## Next\ncontinue\n", with: "")
        #expect(ContextHandoffExtract.find(in: noNext) == .failure(.missing("Open threads")))
        let withThreads = block(threads: "Shall I merge?").replacingOccurrences(of: "## Next\ncontinue\n", with: "")
        #expect(try ContextHandoffExtract.find(in: withThreads).get().next == .wait)
    }

    @Test func waitWithoutOpenThreadsIsRefused() {
        #expect(ContextHandoffExtract.find(in: block(next: "wait")) == .failure(.missing("Open threads")))
    }

    @Test func aBlockFollowedByMoreTextIsNotAHandoff() {
        #expect(ContextHandoffExtract.find(in: block() + "\n\nAnyway, back to the bug.") == .failure(.none))
    }

    @Test func theTemplateItselfIsNotAHandoff() {
        let template = ContextHandoffDirective.text(level: .limit, used: 312_000, limit: 300_000, ceiling: 400_000,
                                                    byButton: false, problem: nil)
        let block = template[template.range(of: "<lostty-handoff>")!.lowerBound...]
            .prefix { _ in true }
        let echoed = String(block[..<block.range(of: "</lostty-handoff>")!.upperBound])
        #expect(ContextHandoffExtract.find(in: "Lostty asked for this:\n" + echoed) == .failure(.none))
    }

    @Test func anUnclosedBlockIsNone() {
        let open = block().replacingOccurrences(of: "</lostty-handoff>", with: "")
        #expect(ContextHandoffExtract.find(in: open) == .failure(.none))
    }
}
#endif
