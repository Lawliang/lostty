#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffWiringTests {
    @Test func theProjectIsTheWorkingDirectorysLastComponent() {
        #expect(ContextHandoffWiring.project(pwd: "/Users/me/projectrepos/lostty") == "lostty")
        #expect(ContextHandoffWiring.project(pwd: nil) == "Terminal")
        #expect(ContextHandoffWiring.project(pwd: "/") == "Terminal")
    }
}
#endif
