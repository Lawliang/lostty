#if os(macOS)
import Testing
import Foundation
@testable import Lostty

struct WhatsNewNotesTests {
    @Test func theFirstEntryIsItsHeadlineParagraphAndBullets() {
        let text = """
        <!--
        # Not this: it's the format help.
        -->

        # Canvas
        Every window on one board,
        zoomed and panned.

        - Pinch to zoom.
        - Scroll the focused terminal,
          pan anywhere else.

        # Older
        - Not shown.
        """
        #expect(WhatsNewNotes.firstEntry(of: text) == WhatsNewNotes(
            headline: "Canvas",
            summary: "Every window on one board, zoomed and panned.",
            bullets: ["Pinch to zoom.", "Scroll the focused terminal, pan anywhere else."]))
    }

    @Test func noHeadlineIsNoEntry() {
        #expect(WhatsNewNotes.firstEntry(of: "- A bullet with no headline") == nil)
        #expect(WhatsNewNotes.firstEntry(of: "<!-- # Only a comment -->") == nil)
    }

    @Test func theShippedFileHasAnEntry() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "WhatsNew", withExtension: "md")
            ?? Bundle.main.url(forResource: "WhatsNew", withExtension: "md"))
        let entry = try #require(WhatsNewNotes.firstEntry(of: String(contentsOf: url, encoding: .utf8)))
        #expect(!entry.headline.isEmpty)
        #expect(!entry.bullets.isEmpty)
    }

    @Test func buildNotesAreItsBullets() {
        #expect(WhatsNewNotes.bullets(ofList: "- One\n\n- Two\nnot a bullet\n- ") == ["One", "Two"])
    }

    @Test func releaseNotesAreTheirListItems() {
        let html = "<ul><li>Canvas &amp; <b>zoom</b></li><li>Fix &lt;tab&gt;</li><li> </li></ul>"
        #expect(WhatsNewNotes.bullets(ofHTML: html) == ["Canvas & zoom", "Fix <tab>"])
    }
}

private final class BundleToken {}

struct WhatsNewBuildTests {
    static let feed = "https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml"

    @Test func aLocalBuildIsItsCommit() {
        #expect(WhatsNewBuild.ids(info: [WhatsNewBuild.commitKey: "abc1234", "CFBundleVersion": "1"])
            == ["commit:abc1234"])
    }

    @Test func aReleaseIsAlsoItsBuildNumber() {
        #expect(WhatsNewBuild.ids(info: [WhatsNewBuild.commitKey: "abc1234", "CFBundleVersion": "202610211200",
                                         UpdateFeed.infoKey: Self.feed])
            == ["commit:abc1234", "version:202610211200"])
    }

    @Test func aDebugBuildIsNothing() {
        #expect(WhatsNewBuild.ids(info: [WhatsNewBuild.commitKey: "", "CFBundleVersion": "1"]).isEmpty)
        #expect(WhatsNewBuild.ids(info: [WhatsNewBuild.commitKey: "$(LOSTTY_BUILD_COMMIT)"]).isEmpty)
        #expect(WhatsNewBuild.ids(info: nil).isEmpty)
    }

    @Test func anInstalledBuildIsReadFromItsFiles() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("WhatsNew-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try (["LosttyBuildCommit": "abc1234"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try "# Canvas\n- Zoom".write(to: resources.appendingPathComponent("WhatsNew.md"), atomically: true, encoding: .utf8)
        try "- Fix tabs".write(to: resources.appendingPathComponent("BuildNotes.md"), atomically: true, encoding: .utf8)
        #expect(WhatsNewBuild.installed(atPath: app.path) == WhatsNewBuild(
            ids: ["commit:abc1234"], entry: WhatsNewNotes(headline: "Canvas", bullets: ["Zoom"]), changes: ["Fix tabs"]))
    }
}

struct WhatsNewCardTests {
    static let canvas = WhatsNewNotes(headline: "Canvas", bullets: ["Zoom"])
    static let old = WhatsNewBuild(ids: ["commit:old"], entry: canvas)
    static let new = WhatsNewBuild(ids: ["commit:new"], entry: canvas, changes: ["Fix tabs"])

    @Test func theFirstWindowOnANewBuildSaysWhatsNew() {
        let next = WhatsNewCard.next(running: Self.new, pending: nil, seen: WhatsNewSeen())
        #expect(next.card == .gotIt(Self.canvas))
        #expect(next.record == [Self.new])
    }

    @Test func onceABuildIsSeenNothingShows() {
        var seen = WhatsNewSeen()
        seen.record(Self.new)
        let next = WhatsNewCard.next(running: Self.new, pending: nil, seen: seen)
        #expect(next.card == nil)
        #expect(next.record.isEmpty)
    }

    @Test func anEntryAlreadyShownGivesWayToTheBuildsCommits() {
        var seen = WhatsNewSeen()
        seen.record(Self.old)
        #expect(WhatsNewCard.next(running: Self.new, pending: nil, seen: seen).card
            == .gotIt(WhatsNewNotes(headline: "What's new in this build", bullets: ["Fix tabs"])))
    }

    @Test func nothingNewToTellShowsNothingButCountsAsSeen() {
        var seen = WhatsNewSeen()
        seen.record(Self.old)
        let quiet = WhatsNewBuild(ids: ["commit:quiet"], entry: Self.canvas)
        let next = WhatsNewCard.next(running: quiet, pending: nil, seen: seen)
        #expect(next.card == nil)
        #expect(next.record == [quiet])
    }

    @Test func aReadyBuildIsOfferedWithWhatsInIt() {
        var seen = WhatsNewSeen()
        seen.record(Self.old)
        let ready = WhatsNewBuild(ids: ["commit:ready"], entry: WhatsNewNotes(headline: "Skins"))
        let next = WhatsNewCard.next(running: Self.old, pending: ready, seen: seen)
        #expect(next.card == .restart(WhatsNewNotes(headline: "Skins")))
        #expect(next.record == [Self.old, ready])
        // Offered once; after the restart it's seen, so no Got It either.
        for build in next.record { seen.record(build) }
        #expect(WhatsNewCard.next(running: Self.old, pending: ready, seen: seen).card == nil)
        #expect(WhatsNewCard.next(running: ready, pending: nil, seen: seen).card == nil)
    }

    @Test func aReadyBuildThatSaysNothingIsStillOffered() {
        let ready = WhatsNewBuild(ids: ["commit:ready"])
        #expect(WhatsNewCard.next(running: Self.old, pending: ready, seen: WhatsNewSeen()).card
            == .restart(WhatsNewCard.readyNotes))
    }

    @Test func anUpdateIsItsReleaseNotesAndMatchesTheReleaseOnceRunning() {
        let update = WhatsNewBuild.update(version: "202610211200", title: "Lostty 0.5",
                                          description: "<ul><li>Canvas</li></ul>")
        var seen = WhatsNewSeen()
        seen.record(Self.old)
        let next = WhatsNewCard.next(running: Self.old, pending: update, seen: seen)
        #expect(next.card == .restart(WhatsNewNotes(headline: "Lostty 0.5", bullets: ["Canvas"])))
        for build in next.record { seen.record(build) }
        let release = WhatsNewBuild(ids: ["commit:rel", "version:202610211200"], entry: Self.canvas)
        #expect(WhatsNewCard.next(running: release, pending: nil, seen: seen).card == nil)
    }

    @Test func aDebugBuildNeverShowsACard() {
        let debug = WhatsNewBuild(ids: [], entry: Self.canvas)
        #expect(WhatsNewCard.next(running: debug, pending: debug, seen: WhatsNewSeen()).card == nil)
    }

    @Test func seenKeepsTheNewestBuilds() {
        var seen = WhatsNewSeen()
        for index in 0..<(WhatsNewSeen.keep + 5) { seen.record(WhatsNewBuild(ids: ["commit:\(index)"])) }
        #expect(seen.builds.count == WhatsNewSeen.keep)
        #expect(seen.builds.first == "commit:\(WhatsNewSeen.keep + 4)")
    }
}
#endif
