#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardRequestViewTests {
    func request(lost: String? = "3 untracked files", reason: String? = "Clear the cache", repo: String? = "/r") -> GuardRequest {
        GuardRequest(id: 4, check: GuardCheck(v: 1, pane: UUID().uuidString, agent: "claude", session: nil, tool: "Bash",
                                              input: "rm -rf cache", cwd: "/r/sub", repo: repo, branch: "feature",
                                              group: "deleting", why: "deletes files git can't restore", lost: lost, reason: reason),
                     created: Date(), state: .pending, decided: nil)
    }

    @Test func theGuardsAssessmentIsLabeledApartFromTheContext() {
        let r = request()
        #expect(GuardRequestFacts.assessment(r).map(\.label) == ["Kind", "Why", "Would lose"])
        #expect(GuardRequestFacts.assessment(r).first?.value == "Deleting")
        let rows = GuardRequestFacts.context(r)
        #expect(rows.map(\.label) == ["Folder", "Repo", "How it came about", "The agent says"])
        #expect(rows.first { $0.label == "Repo" }?.value == "/r · feature")
        #expect(rows.last?.value == "Clear the cache")
    }

    @Test func optionalFactsAreLeftOut() {
        let r = request(lost: nil, reason: nil, repo: nil)
        #expect(GuardRequestFacts.assessment(r).map(\.label) == ["Kind", "Why"])
        #expect(GuardRequestFacts.context(r).map(\.label) == ["Folder", "How it came about"])
    }

    @Test func theWholeToolInputIsShownForAllButBash() {
        var c = request().check
        c.toolInput = #"{"command":"rm -rf cache"}"#
        #expect(GuardRequestFacts.toolInput(c) == nil)
        c.tool = "Write"
        c.input = "/Users/me/notes.md"
        c.toolInput = #"{"content":"hello","file_path":"/Users/me/notes.md"}"#
        #expect(GuardRequestFacts.toolInput(c) == .text(#"{"content":"hello","file_path":"/Users/me/notes.md"}"#))
        c.toolInput = "sha256:abc"
        c.toolInputBytes = 300_000
        #expect(GuardRequestFacts.toolInput(c) == .tooLarge(300_000))
    }
}
#endif
