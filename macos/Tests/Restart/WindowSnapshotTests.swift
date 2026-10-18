#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct WindowSnapshotTests {
    /// "a1", "a2" are tabs of one window; the rest stand alone.
    let tabs: [String: [String]] = ["a1": ["a1", "a2"], "a2": ["a1", "a2"]]

    @Test func tabsStayTogetherInTabOrder() {
        let groups = WindowSnapshot.arrange(["a2", "b", "a1"], tabs: { tabs[$0] ?? [] }, frontToBack: ["a2", "b"])
        #expect(groups == [["a1", "a2"], ["b"]])
    }

    @Test func groupsGoFrontToBack() {
        let groups = WindowSnapshot.arrange(["a1", "b", "c"], tabs: { tabs[$0] ?? [] }, frontToBack: ["c", "a2", "b"])
        #expect(groups == [["c"], ["a1", "a2"], ["b"]])
    }

    @Test func windowsOffScreenComeLastInTheOrderFound() {
        // Minimized windows aren't in the on-screen order.
        let groups = WindowSnapshot.arrange(["m", "b", "n"], tabs: { _ in [] }, frontToBack: ["b"])
        #expect(groups == [["b"], ["m"], ["n"]])
    }

    @Test func aFrameOnAScreenStays() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let frame = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(WindowSnapshot.placement(frame, screens: screens) == frame)
        // Mostly off the edge, but enough left to grab.
        let edge = CGRect(x: -760, y: 100, width: 800, height: 600)
        #expect(WindowSnapshot.placement(edge, screens: screens) == edge)
    }

    @Test func aFrameOnADisplayThatsGoneIsDropped() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        #expect(WindowSnapshot.placement(CGRect(x: 1600, y: 100, width: 800, height: 600), screens: screens) == nil)
        #expect(WindowSnapshot.placement(CGRect(x: 1430, y: 100, width: 800, height: 600), screens: screens) == nil)
    }

    @Test func theHandoffCarriesTheSnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("restart.json")
        let snapshot = WindowSnapshot(groups: [
            .init(frame: CGRect(x: 10, y: 20, width: 800, height: 600), selected: 1, miniaturized: false,
                  tabs: [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8)]),
        ])
        let handoff = RestartHandoff(
            pid: 1, at: Date(timeIntervalSince1970: 2_000_000_000), claude: [:], stayAwakeOn: false,
            stayAwakeUntil: nil, hookAgents: [], keepWindows: nil, windows: snapshot)
        try handoff.save(to: url)
        #expect(RestartHandoff.peek(at: url)?.windows == snapshot)
        // Peeking leaves it for resumeIfRestarted to take.
        #expect(RestartHandoff.take(from: url)?.windows == snapshot)
        #expect(RestartHandoff.peek(at: url) == nil)
    }

    @Test func anOlderBuildsHandoffHasNoSnapshot() throws {
        let json = """
        {"pid":1,"at":2000000000,"claude":{},"stayAwakeOn":false,"hookAgents":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let handoff = try decoder.decode(RestartHandoff.self, from: Data(json.utf8))
        #expect(handoff.windows == nil)
    }
}
#endif
