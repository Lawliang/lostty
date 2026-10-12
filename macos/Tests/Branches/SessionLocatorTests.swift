#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SessionLocatorTests {
    @Test func phonePanesMapSessionsToTheirActivePanesFolder() {
        let output = """
        $1\t0\t/r/other
        $1\t1\t/r/repo
        $2\t1\t/r/two with space
        bad line
        $3\t1\t

        """
        #expect(PhonePanes.activePaths(output) == ["$1": "/r/repo", "$2": "/r/two with space"])
    }

    @Test func agentStatePrefersWaitingThenWorkingThenIdle() {
        #expect(SessionLocator.agentState(phase: true, awaiting: true, claudeOpen: true) == .waiting)
        #expect(SessionLocator.agentState(phase: true, awaiting: false, claudeOpen: true) == .working)
        #expect(SessionLocator.agentState(phase: false, awaiting: false, claudeOpen: true) == .idle)
        #expect(SessionLocator.agentState(phase: false, awaiting: false, claudeOpen: false) == nil)
    }
}
#endif
