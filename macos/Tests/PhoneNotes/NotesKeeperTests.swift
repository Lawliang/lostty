#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

@MainActor
struct NotesKeeperTests {
    func folder() throws -> NotesFolder {
        let folder = NotesFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("keeper-\(UUID().uuidString)"))
        try folder.create()
        return folder
    }

    func waiting(_ id: String = "$1") -> RemoteSession {
        RemoteSession(
            id: id, name: "lostty", surface: "PANE", owner: 1, claude: .waiting, action: "Run the iOS tests",
            title: "✳ Fix it", path: "/tmp", command: "2.1.296")
    }

    @Test func aListingThatFailedWhileTheServerRunsIsUnknown() {
        let session = waiting()
        #expect(NotesKeeper.listing(nil, serverExists: true) == nil)
        #expect(NotesKeeper.listing(nil, serverExists: false) == [])
        #expect(NotesKeeper.listing([session], serverExists: true) == [session])
    }

    @Test func anUnknownListingLeavesTheNotesAlone() throws {
        let keeper = NotesKeeper(folder: try folder(), list: { nil }, signal: {})
        keeper.start()
        keeper.apply(listing: [waiting()])
        keeper.apply(listing: nil)
        #expect(keeper.log.notes.count == 1)
        #expect(!keeper.log.notes[0].read)
        #expect(keeper.log.waiting == ["$1"])
    }

    @Test func takesOverOnceTheOtherLosttyLetsGo() throws {
        let folder = try folder()
        let other = try #require(folder.lock())
        let keeper = NotesKeeper(folder: folder, list: { [] }, signal: {})
        keeper.start()
        #expect(!keeper.isKeeping)
        close(other)
        keeper.sessionsChanged()
        #expect(keeper.isKeeping)
    }
}
#endif
