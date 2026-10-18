#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct AgentCoordinationTests {
    @Test func onlyAnExactTrueTurnsItOn() {
        func on(_ json: String) -> Bool { AgentCoordination.isOn(json: Data(json.utf8)) }
        #expect(on(#"{"enabled": true}"#))
        #expect(!on(#"{"enabled": false}"#))
        #expect(!on("{}"))
        #expect(!on("not json"))
        // A number or a string is off, as the CLI reads it.
        #expect(!on(#"{"enabled": 1}"#))
        #expect(!on(#"{"enabled": "true"}"#))
        // Only the global setting counts, not a repo's.
        #expect(!on(#"{"repos": {"/r": {"enabled": true}}}"#))
    }

    @Test func aMissingFileIsOff() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(!AgentCoordination.isOn(home: home))
        let dir = home.appendingPathComponent(".config/lostty")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(#"{"enabled": true}"#.utf8).write(to: dir.appendingPathComponent("guard.json"))
        #expect(AgentCoordination.isOn(home: home))
    }
}
#endif
