#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RestartHandoffTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func handoff(pid: Int32 = 4242, ago: TimeInterval = 5) -> RestartHandoff {
        RestartHandoff(
            pid: pid, at: now.addingTimeInterval(-ago),
            claude: ["ABCDEF01-0000-4000-8000-000000000001": ClaudeCarry(activity: .waiting, action: "Run the tests")],
            stayAwakeOn: true, stayAwakeUntil: nil, hookAgents: ["claude"], keepWindows: nil)
    }

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aRecentHandoffFromAnExitedLosttyIsFresh() {
        #expect(handoff().isFresh(now: now, isAlive: { _ in false }))
    }

    @Test func aStaleOrLiveHandoffIsNotFresh() {
        #expect(!handoff(ago: RestartHandoff.maxAge + 1).isFresh(now: now, isAlive: { _ in false }))
        #expect(!handoff().isFresh(now: now, isAlive: { _ in true }))
        #expect(!handoff(ago: -30).isFresh(now: now, isAlive: { _ in false }))
    }

    @Test func takeReadsItOnceAndDeletesIt() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        try handoff().save(to: url)
        #expect(RestartHandoff.take(from: url) == handoff())
        #expect(RestartHandoff.take(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anUnreadableHandoffIsDeletedAndIgnored() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        try Data("{not json".utf8).write(to: url)
        #expect(RestartHandoff.take(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func eachBuildHasItsOwnHandoff() throws {
        let dir = try folder()
        #expect(RestartHandoff.url(bundleID: "com.lawliang.lostty", in: dir)
            != RestartHandoff.url(bundleID: "com.lawliang.lostty.debug", in: dir))
    }

    @Test func anOlderHandoffWithoutTranscriptsStillReads() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        let json = #"{"pid":4242,"at":1999999995,"claude":{},"stayAwakeOn":false,"hookAgents":[]}"#
        try Data(json.utf8).write(to: url)
        let taken = try #require(RestartHandoff.take(from: url))
        #expect(taken.transcripts == nil)
    }

    @Test func transcriptsRoundTrip() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        var saved = handoff()
        saved.transcripts = ["ABCDEF01-0000-4000-8000-000000000001": "/Users/a/.claude/projects/p/s.jsonl"]
        try saved.save(to: url)
        #expect(RestartHandoff.take(from: url) == saved)
    }
}
#endif
