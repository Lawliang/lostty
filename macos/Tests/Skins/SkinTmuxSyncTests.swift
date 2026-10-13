#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct SkinTmuxSyncTests {
    let a = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!

    @Test func aSkinGivesThePhoneItsColors() {
        var skin = AutoSkin.skin(forRepo: "lostty", textureOpacity: 0.1)
        #expect(skin.sessionSkin().foreground == nil)
        #expect(skin.sessionSkin().background == SessionSkin.RGB(r: skin.background.r, g: skin.background.g, b: skin.background.b))
        skin.foreground = RGB(r: 0xe0, g: 0xe0, b: 0xe0)
        #expect(SessionSkin(encoded: skin.sessionSkin().encoded) == skin.sessionSkin())
    }

    @Test func writesAndClearsTheSkinOption() {
        let sessions = [
            RemoteSession(id: "$1", name: "p", surface: a.uuidString, owner: 100),
            RemoteSession(id: "$2", name: "q", surface: "B", owner: 100, skin: SessionSkin(encoded: "1c1c1c,,e5199c")),
        ]
        let args = TmuxOptionSync.args(
            option: TmuxRemote.skinOption, desired: [a.uuidString: "1c1c1c,,e5199c"], current: { $0.skin?.encoded },
            sessions: sessions, pid: 100)
        #expect(args == [
            "set-option", "-t", "$1", "@lostty_skin", "1c1c1c,,e5199c", ";",
            "set-option", "-u", "-t", "$2", "@lostty_skin", ";",
            "wait-for", "-S", "lostty-changed",
        ])
    }
}
#endif
