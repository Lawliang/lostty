#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ClaudeMessageTests {
    private func b64(_ json: String) -> String { Data(json.utf8).base64EncodedString() }

    @Test func decodesEachState() {
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"busy"}"#)) == .busy)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"idle"}"#)) == .idle)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"exit"}"#)) == .exit)
    }

    @Test func ignoresExtraFields() {
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"busy","tokens":42}"#)) == .busy)
    }

    @Test func rejectsUnknownVersionStateAndGarbage() {
        #expect(ClaudeMessage.decode(b64(#"{"v":2,"state":"busy"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"thinking"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64(#"{"state":"busy"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64("[1]")) == nil)
        #expect(ClaudeMessage.decode("%%%not base64") == nil)
        #expect(ClaudeMessage.decode("") == nil)
    }

    @Test func matchesTheZigEncoder() {
        // Exact bytes produced by `+claude-state busy` (see protocol.zig).
        #expect(ClaudeMessage.decode("eyJ2IjoxLCJzdGF0ZSI6ImJ1c3kifQ==") == .busy)
    }
}
#endif
