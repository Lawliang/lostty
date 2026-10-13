#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GitTests {
    @Test func runsGitInADirectory() throws {
        let repo = try TempRepo.make()
        let head = try #require(Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo.root))
        #expect(head == "main\n")
    }

    @Test func aFailingCommandIsNil() throws {
        let dir = try TempRepo.makeDirectory()
        #expect(Git.run(["rev-parse", "HEAD"], in: dir) == nil)
    }

    @Test func aMissingDirectoryIsNil() {
        #expect(Git.run(["status"], in: "/nonexistent/\(UUID().uuidString)") == nil)
    }
}
#endif
