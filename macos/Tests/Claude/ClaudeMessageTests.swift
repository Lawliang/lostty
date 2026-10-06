#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

/// The core base64-decodes SetUserVar values (Surface.decodeUserVar), so
/// the app receives the JSON text itself.
struct ClaudeMessageTests {
    @Test func decodesEachState() {
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"busy"}"#) == .busy)
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"idle"}"#) == .idle)
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"exit"}"#) == .exit)
    }

    @Test func ignoresExtraFields() {
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"busy","tokens":42}"#) == .busy)
    }

    @Test func rejectsUnknownVersionStateAndGarbage() {
        #expect(ClaudeMessage.decode(#"{"v":2,"state":"busy"}"#) == nil)
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"thinking"}"#) == nil)
        #expect(ClaudeMessage.decode(#"{"state":"busy"}"#) == nil)
        #expect(ClaudeMessage.decode("[1]") == nil)
        #expect(ClaudeMessage.decode("eyJ2IjoxLCJzdGF0ZSI6ImJ1c3kifQ==") == nil)
        #expect(ClaudeMessage.decode("") == nil)
    }

    @Test func matchesTheZigEncoder() {
        // Exact JSON `+claude-state busy` encodes (see protocol.zig).
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"busy"}"#) == .busy)
    }
}
#endif
