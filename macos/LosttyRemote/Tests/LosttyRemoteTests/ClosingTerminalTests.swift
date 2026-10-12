import Foundation
import Testing
@testable import LosttyRemote

struct ClosingTerminalTests {
    final class Fake: RemoteTerminal, @unchecked Sendable {
        var events: [String] = []
        func write(_ data: Data) { events.append("write") }
        func resize(cols: Int, rows: Int) { events.append("resize") }
        func close() { events.append("close") }
    }

    @Test func closeClosesTheChannelThenTheConnection() {
        let fake = Fake()
        nonisolated(unsafe) var closedConnection = 0
        let terminal = ClosingTerminal(fake) { closedConnection += 1 }
        terminal.write(Data())
        terminal.resize(cols: 1, rows: 1)
        terminal.close()
        #expect(fake.events == ["write", "resize", "close"])
        #expect(closedConnection == 1)
    }
}
