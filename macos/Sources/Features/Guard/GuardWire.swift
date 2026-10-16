#if os(macOS)
import Foundation

/// What `lostty +guard` sends for a critical tool call: one JSON line on
/// the guard socket (src/cli/guard/wire.zig). Field names are the wire's.
struct GuardCheck: Codable, Equatable, Sendable {
    var v: Int
    var pane: String
    var agent: String
    var session: String?
    var tool: String
    var input: String
    var cwd: String
    var repo: String?
    var branch: String?
    var group: String
    var why: String
    var lost: String?
    var reason: String?
    /// The whole tool input, canonical JSON (or `sha256:<hex>` when large).
    /// An approval keys it, so one for a Write or an MCP call never covers
    /// different content or arguments.
    var toolInput: String? = nil
    /// The tool input's size when `toolInput` is only its hash.
    var toolInputBytes: Int? = nil

    /// "Exactly this call": the same pane, tool, folder, input and whole
    /// tool input, compared field by field.
    struct Key: Equatable, Sendable {
        var pane: String
        var tool: String
        var cwd: String
        var input: String
        var toolInput: String?
    }

    var key: Key { Key(pane: pane, tool: tool, cwd: cwd, input: input, toolInput: toolInput) }

    /// As the guard's catalog labels its groups.
    var groupLabel: String {
        switch group {
        case "deleting": "Deleting"
        case "discarding": "Throwing work away"
        case "leaving": "Leaving the Mac"
        case "merging": "Merging into a protected branch"
        case "guardrails": "Changing the guardrails"
        case "outside": "Writing outside the project"
        default: "A command Lostty can't read"
        }
    }

    var agentName: String { agent == "codex" ? "Codex" : "Claude" }
}

/// The app's only answers: let this one call through (an approval you gave
/// is used up), or not, with the request to show. There is no reply that
/// grants anything.
struct GuardReply: Codable, Equatable, Sendable {
    var v = 1
    var decision: String
    var request: Int?

    static let allow = GuardReply(decision: "allow", request: nil)
    static func deny(_ id: Int) -> GuardReply { GuardReply(decision: "deny", request: id) }
}
#endif
