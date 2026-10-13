#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct BranchesFormatTests {
    @Test func aheadBehind() {
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 2, behind: 1)) == "↑2 ↓1")
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 3, behind: 0)) == "↑3")
        #expect(BranchesFormat.aheadBehind(AheadBehind(ahead: 0, behind: 0)) == "even")
        #expect(BranchesFormat.aheadBehind(nil) == nil)
    }

    @Test func upstream() {
        #expect(BranchesFormat.upstream(.none) == "Not pushed")
        #expect(BranchesFormat.upstream(.gone(name: "origin/x")) == "origin/x was deleted")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 0, behind: 0)) == "Up to date with origin/x")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 2, behind: 0)) == "2 to push to origin/x")
        #expect(BranchesFormat.upstream(.tracking(name: "origin/x", ahead: 1, behind: 3)) == "1 to push, 3 to pull · origin/x")
    }

    @Test func counts() {
        #expect(BranchesFormat.count(1, "file") == "1 file")
        #expect(BranchesFormat.count(4, "file") == "4 files")
    }

    @Test func initials() {
        #expect(BranchesFormat.initial("zsh") == "Z")
        #expect(BranchesFormat.initial("✳ Claude") == "C")
        #expect(BranchesFormat.initial("") == "•")
    }
}
#endif
