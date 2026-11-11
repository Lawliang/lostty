#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct ClaudeModelSwitchTests {
    @Test func readsTheCatalogInOrder() {
        let json = #"""
        {"catalog": {"config": {"models": [
            {"id": "claude-opus-5-5", "name": "Opus 5.5"},
            {"id": "claude-fable-5-2", "name": "Fable 5.2"},
            {"id": "claude-opus-5-5", "name": "Again"},
            {"id": "bad id; rm", "name": "Bad"},
            {"id": "claude-x"}
        ]}}}
        """#
        #expect(ClaudeModelSwitch.models(fromCatalog: Data(json.utf8)) == [
            AgentModel(id: "claude-opus-5-5", name: "Opus 5.5"),
            AgentModel(id: "claude-fable-5-2", name: "Fable 5.2"),
            AgentModel(id: "claude-x", name: "claude-x"),
        ])
    }

    @Test func noCatalogFallsBackToTheAliases() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ClaudeModelSwitch.models(in: folder) == TerminalAgent.claude.fallbackModels)
    }
}
#endif
