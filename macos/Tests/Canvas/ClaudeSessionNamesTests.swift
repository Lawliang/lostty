#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ClaudeSessionNamesTests {
    private func file(pid: Int32, tmux: String?, name: String?, at: Double = 0) -> Data {
        var fields: [String: Any] = ["pid": pid, "updatedAt": at, "kind": "interactive"]
        fields["tmux"] = tmux
        fields["name"] = name
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    @Test func eachTmuxSessionGetsItsClaudesName() {
        let files = [
            file(pid: 1, tmux: "zones-2:@50.%50", name: "zones-f9"),
            file(pid: 2, tmux: "more-UI-improvements:@45.%45", name: "more-ui-improvements-af"),
        ]
        #expect(ClaudeSessionNames.names(files) { _ in true }
            == ["zones-2": "zones-f9", "more-UI-improvements": "more-ui-improvements-af"])
    }

    @Test func aDeadProcessesFileIsSkipped() {
        let files = [file(pid: 1, tmux: "zones-2:@50.%50", name: "zones-f9")]
        #expect(ClaudeSessionNames.names(files) { _ in false }.isEmpty)
    }

    @Test func outsideTmuxOrWithoutANameIsSkipped() {
        let files = [file(pid: 1, tmux: nil, name: "idfk-97"), file(pid: 2, tmux: "idfk:@1.%1", name: nil), Data("{".utf8)]
        #expect(ClaudeSessionNames.names(files) { _ in true }.isEmpty)
    }

    @Test func twoInOneSessionKeepTheLatest() {
        let files = [
            file(pid: 1, tmux: "zones-2:@50.%50", name: "zones-f9", at: 20),
            file(pid: 2, tmux: "zones-2:@50.%50", name: "zones-11", at: 10),
        ]
        #expect(ClaudeSessionNames.names(files) { _ in true } == ["zones-2": "zones-f9"])
    }
}
#endif
