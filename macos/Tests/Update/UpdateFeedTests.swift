#if os(macOS)
import Testing
import Foundation
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

    @Test func noFeedNeverChecks() {
        for setting: Ghostty.Config.AutoUpdate? in [nil, .off, .check, .download] {
            #expect(UpdateFeed.schedule(hasFeed: false, autoUpdate: setting)
                == UpdateFeed.Schedule(checks: false, downloads: false))
        }
    }

    @Test func aFeedChecksAndAsksFirst() {
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: nil) == UpdateFeed.Schedule(checks: true, downloads: false))
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .check) == UpdateFeed.Schedule(checks: true, downloads: false))
    }

    @Test func theAutoUpdateSettingStillWins() {
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .off) == UpdateFeed.Schedule(checks: false, downloads: false))
        #expect(UpdateFeed.schedule(hasFeed: true, autoUpdate: .download) == UpdateFeed.Schedule(checks: true, downloads: true))
    }

    @Test func checkingOnALocalBuildExplainsWhy() {
        #expect(UpdateFeed.checkAction(feed: nil) == .explainLocalBuild)
        #expect(UpdateFeed.checkAction(feed: Self.feed) == .sparkle)
        #expect(UpdateFeed.localBuildMessage == "This copy of Lostty was built on this Mac; it updates with install.sh.")
    }

    @Test func theAppChecksDaily() {
        let info = Bundle(for: UpdateController.self).infoDictionary
        #expect(info?["SUScheduledCheckInterval"] as? Int == 86400)
        #expect(info?["SUEnableAutomaticChecks"] == nil)
    }
}
#endif
