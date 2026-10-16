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

    @Test func factsInOrderWithTheAgentsWordsLabeled() {
        let rows = GuardRequestFacts.rows(request())
        #expect(rows.map(\.label) == ["Why", "Would lose", "Folder", "Repo", "How it came about", "The agent says"])
        #expect(rows.first { $0.label == "Repo" }?.value == "/r · feature")
        #expect(rows.last?.value == "Clear the cache")
    }

    @Test func optionalFactsAreLeftOut() {
        let rows = GuardRequestFacts.rows(request(lost: nil, reason: nil, repo: nil))
        #expect(rows.map(\.label) == ["Why", "Folder", "How it came about"])
    }
}
#endif
