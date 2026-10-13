#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct NewTerminalRequestsTests {
    @Test func theLaunchersNameIsTemporary() throws {
        let pane = try #require(UUID(uuidString: "5CF44536-1111-2222-3333-444455556666"))
        #expect(NewTerminalRequests.isTemporaryName("lostty-5cf44536-20285", of: pane))
        #expect(!NewTerminalRequests.isTemporaryName("lostty-4", of: pane))
        #expect(!NewTerminalRequests.isTemporaryName("lostty", of: pane))
        // Another pane's temporary name isn't this one's.
        #expect(!NewTerminalRequests.isTemporaryName("lostty-2023e142-22418", of: pane))
    }
}
#endif
