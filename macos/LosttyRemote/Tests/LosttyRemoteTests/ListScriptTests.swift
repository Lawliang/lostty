#if os(macOS)
import Foundation
import Testing
@testable import LosttyRemote

/// Runs the list script in /bin/sh over folders made to look like repos.
struct ListScriptTests {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("list-script-\(UUID().uuidString)")
        // A dotfiles repo in the home folder: never anyone's project.
        try write("home/.git/HEAD", "ref: refs/heads/dotfiles\n")
        try write("home/code/lostty/.git/HEAD", "ref: refs/heads/skins\n")
        try mkdir("home/code/lostty/macos/Sources")
        try write("home/code/lostty/.git/worktrees/stay/HEAD", "ref: refs/heads/stay-awake\n")
        try write(
            "home/code/lostty/.claude/worktrees/stay/.git",
            "gitdir: \(root.path)/home/code/lostty/.git/worktrees/stay\n")
        try write("home/code/rel/.git", "gitdir: .git-real\n")
        try write("home/code/rel/.git-real/HEAD", "ref: refs/heads/feature/login\n")
        try write("home/code/detached/.git/HEAD", "3f2a9c1e0b7d4a6f8e2c1b0a9d8c7e6f5a4b3c2d\n")
        try write("home/code/my proj/.git/HEAD", "ref: refs/heads/main\n")
        try mkdir("home/notes")
        try mkdir("elsewhere")
    }

    private func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// (exit status, parsed listing) for sessions in `folders`, each owned
    /// by `owner` (a pid; empty for none).
    private func run(_ folders: [String], owner: String = "", claude: String = "waiting") throws -> (Int32, [RemoteSession]) {
        try run(folders.map { ($0, owner) }, claude: claude)
    }

    private func run(
        _ sessions: [(folder: String, owner: String)], claude: String = "waiting"
    ) throws -> (Int32, [RemoteSession]) {
        let lines = sessions.enumerated().map { i, session in
            let path = root.appendingPathComponent(session.folder).path
            return "\(path)\t\(session.owner)\t$\(i)\tx\tPANE\t\(session.owner)\t\t\(claude)\t1\tzsh\t\(path)\t\t\t\tt\n"
        }.joined()
        let input = root.appendingPathComponent("listing")
        try lines.write(to: input, atomically: true, encoding: .utf8)
        return try run(listing: "cat \(TmuxRemote.shellQuote(input.path))")
    }

    /// Every session's pane shows `pane`.
    private func run(listing: String, pane: String = "") throws -> (Int32, [RemoteSession]) {
        let paneFile = root.appendingPathComponent("pane")
        try pane.write(to: paneFile, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", TmuxRemote.listScript(listing: listing, capture: "cat \(TmuxRemote.shellQuote(paneFile.path)); :"),
        ]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, TmuxRemote.parseListing(String(decoding: data, as: UTF8.self)))
    }

    @Test func aWorkingClaudeGetsItsWorkingLine() throws {
        let listing = root.appendingPathComponent("listing")
        let path = root.appendingPathComponent("home/notes").path
        try ["working", "agents", "waiting", ""].enumerated().map { i, claude in
            "\(path)\t\t$\(i)\tx\tPANE\t\t\t\(claude)\t1\t2.1.296\t\(path)\t\t\t\tt\n"
        }.joined().write(to: listing, atomically: true, encoding: .utf8)
        // The working line sits just over the prompt; older ones scrolled up.
        let pane = """
            ⏺ Done with the first part.
            ✻ Pondering… (2s · ↓ 10 tokens)
              ⎿  Running…
            ✳ Incubating… (3m 51s · ↓ 23.5k tokens)
            ────────────
            > 	

            """
        let (status, sessions) = try run(listing: "cat \(TmuxRemote.shellQuote(listing.path))", pane: pane)
        #expect(status == 0)
        #expect(sessions.map(\.spinner?.word) == ["Incubating…", "Incubating…", nil, nil])
        #expect(sessions.first?.spinner?.elapsed == 231)
        #expect(sessions.first?.spinner?.detail == "↓ 23.5k tokens")
        #expect(sessions.map(\.id) == ["$0", "$1", "$2", "$3"])
    }

    @Test func eachSessionGetsItsRepoAndBranch() throws {
        let (status, sessions) = try run([
            "home/code/lostty",
            "home/code/lostty/macos/Sources",
            "home/code/lostty/.claude/worktrees/stay",
            "home/code/rel",
            "home/code/detached",
            "home/code/my proj",
            "home/notes",
            "elsewhere",
        ])
        #expect(status == 0)
        #expect(sessions.map(\.repo) == ["lostty", "lostty", "lostty", "rel", "detached", "my proj", nil, nil])
        #expect(sessions.map(\.branch) == ["skins", "skins", "stay-awake", "feature/login", nil, "main", nil, nil])
        #expect(sessions.map(\.id) == ["$0", "$1", "$2", "$3", "$4", "$5", "$6", "$7"])
    }

    @Test func aGoneLosttysSessionsHaveNoOwner() throws {
        // A pid that ran and exited: what a crashed Lostty leaves in tmux.
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()
        let me = String(ProcessInfo.processInfo.processIdentifier)
        let (status, sessions) = try run([
            ("home/notes", me), ("home/notes", String(gone.processIdentifier)), ("home/notes", ""),
        ])
        #expect(status == 0)
        #expect(sessions.map(\.owner) == [ProcessInfo.processInfo.processIdentifier, nil, nil])
        // So its stale "waiting" reads as last used, without a Mac window.
        let row = SessionLabel.row(for: sessions[1], now: Date())
        #expect(row.status == .lastUsed(SessionLabel.relative(sessions[1].activity, now: Date())))
        #expect(!row.openOnMac)
    }

    @Test func tmuxsFailureIsTheScripts() throws {
        #expect(try run(listing: "exit 1").0 == 1)
        #expect(try run(listing: "no-such-tmux-command").0 == 127)
    }

    @Test func noSessionsIsAnEmptyList() throws {
        let (status, sessions) = try run(listing: "true")
        #expect(status == 0)
        #expect(sessions.isEmpty)
    }
}
#endif
