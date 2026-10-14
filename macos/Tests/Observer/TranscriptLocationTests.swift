#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TranscriptLocationTests {
    /// A fake home with Claude's and Codex's folders, one conversation in
    /// each, and a secret outside them.
    struct Home {
        let root: String
        var claude: String { root + "/.claude/projects/-proj/s.jsonl" }
        var codex: String { root + "/.codex/sessions/2026/10/14/rollout-x.jsonl" }
        var secret: String { root + "/secret.jsonl" }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)").path
            for file in [root + "/.claude/projects/-proj/s.jsonl", root + "/.codex/sessions/2026/10/14/rollout-x.jsonl",
                         root + "/secret.jsonl"] {
                try FileManager.default.createDirectory(
                    atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: file, contents: Data("{}\n".utf8))
            }
        }
    }

    @Test func claudesAndCodexsConversationsAreAllowed() throws {
        let home = try Home()
        #expect(TranscriptLocation.allowed(home.claude, home: home.root, environment: [:])?.agent == .claude)
        #expect(TranscriptLocation.allowed(home.codex, home: home.root, environment: [:])?.agent == .codex)
    }

    @Test func anythingElseIsNot() throws {
        let home = try Home()
        #expect(TranscriptLocation.allowed(home.secret, home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed("/etc/passwd", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(".claude/projects/-proj/s.jsonl", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(home.root + "/.claude/projects/-proj/../../secret.jsonl",
                                           home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(home.root + "/.claude/projects/-proj/missing.jsonl",
                                           home: home.root, environment: [:]) == nil)
        let notJSONL = home.root + "/.claude/projects/-proj/notes.txt"
        FileManager.default.createFile(atPath: notJSONL, contents: Data())
        #expect(TranscriptLocation.allowed(notJSONL, home: home.root, environment: [:]) == nil)
    }

    @Test func aSymlinkOutOfTheFoldersIsNotFollowed() throws {
        let home = try Home()
        let link = home.root + "/.claude/projects/-proj/link.jsonl"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: home.secret)
        #expect(TranscriptLocation.allowed(link, home: home.root, environment: [:]) == nil)
    }

    @Test func theAgentsOwnConfigFoldersCount() throws {
        let home = try Home()
        let custom = home.root + "/custom-claude"
        try FileManager.default.createDirectory(atPath: custom + "/projects/p", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: custom + "/projects/p/s.jsonl", contents: Data())
        #expect(TranscriptLocation.allowed(custom + "/projects/p/s.jsonl", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(custom + "/projects/p/s.jsonl", home: home.root,
                                           environment: ["CLAUDE_CONFIG_DIR": custom])?.agent == .claude)
    }
}
#endif
