#if os(macOS)
import Testing
@testable import Lostty

struct UpdateFeedTests {
    static let feed = "https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml"

    @Test func aReleaseBuildHasItsFeed() {
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: Self.feed]) == Self.feed)
    }

    @Test func aBuildMadeOnThisMacHasNone() {
        #expect(UpdateFeed.url(info: nil) == nil)
        #expect(UpdateFeed.url(info: [:]) == nil)
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: ""]) == nil)
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: "$(LOSTTY_UPDATE_FEED)"]) == nil)
    }

    @Test func onlyLosttysOwnFeed() {
        for other in [
            "https://release.files.ghostty.org/appcast.xml",
            "http://github.com/Lawliang/lostty/releases/latest/download/appcast.xml",
            "https://github.com/Lawliang/lostty-fork/releases/latest/download/appcast.xml",
            "https:",
        ] {
            #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: other]) == nil)
        }
        #expect(UpdateFeed.url(info: [UpdateFeed.infoKey: 42]) == nil)
    }
}
#endif
