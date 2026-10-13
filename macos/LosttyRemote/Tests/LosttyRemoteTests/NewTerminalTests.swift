import Foundation
import Testing
@testable import LosttyRemote

struct NewTerminalTests {
    @Test func aRequestRoundTripsAndNamesItsOptions() throws {
        let request = NewTerminalRequest(
            folder: "/Users/me/projectrepos/lostty", branch: "feature/login", agent: .claude, id: "0123456789ab")
        #expect(request.requestOption == "@lostty_new_0123456789ab")
        #expect(request.answerOption == "@lostty_made_0123456789ab")
        #expect(NewTerminalRequest(encoded: request.encoded) == request)
        #expect(NewTerminalRequest.id(ofRequestOption: "@lostty_new_0123456789ab") == "0123456789ab")
        #expect(NewTerminalRequest.id(ofRequestOption: "@lostty_new_xyz") == nil)
        #expect(NewTerminalRequest.id(ofRequestOption: "@lostty_skin") == nil)
        #expect(NewTerminalRequest.isID(NewTerminalRequest.newID()))
    }

    @Test func eachAgentRoundTripsWithItsCommand() throws {
        for agent in [TerminalAgent.claude, .codex, nil] {
            let request = NewTerminalRequest(folder: "/x", agent: agent, id: "0123456789ab")
            #expect(NewTerminalRequest(encoded: request.encoded)?.agent == agent)
        }
        #expect(TerminalAgent.claude.command == "claude" && TerminalAgent.codex.command == "codex")
        // Options become their fixed arguments, in the agent's order; others are ignored.
        let codex = NewTerminalRequest(folder: "/x", agent: .codex, agentOptions: ["search", "resume", "rm -rf"], id: "0123456789ab")
        #expect(NewTerminalRequest(encoded: codex.encoded)?.startCommand == "codex resume --last --search")
        // Options it doesn't have are ignored.
        #expect(TerminalAgent.claude.commandLine(["skipPermissions", "continue"]) == "claude")
        #expect(TerminalAgent.claude.commandLine([]) == "claude")
        #expect(NewTerminalRequest(folder: "/x", agent: nil, agentOptions: ["continue"]).startCommand == nil)
        // An agent this version doesn't know: not a request it can act on.
        #expect(NewTerminalRequest(encoded: #"{"id":"0123456789ab","folder":"/x","agent":"gemini"}"#) == nil)
    }

    @Test func aModelGoesAfterTheOptions() {
        let codex = NewTerminalRequest(folder: "/x", agent: .codex, agentOptions: ["resume"], model: "gpt-6-sol", id: "0123456789ab")
        #expect(NewTerminalRequest(encoded: codex.encoded)?.startCommand == "codex resume --last -m gpt-6-sol")
        #expect(TerminalAgent.claude.commandLine([], model: "claude-opus-4-8") == "claude --model claude-opus-4-8")
        // Only names it could type plainly.
        #expect(TerminalAgent.claude.commandLine([], model: "opus; rm -rf ~") == "claude")
        #expect(!AgentModel.isName("-x") && !AgentModel.isName("a b") && AgentModel.isName("claude-opus-5-5"))
        let bad = NewTerminalRequest(folder: "/x", agent: .claude, model: "$(boom)", id: "0123456789ab")
        #expect(NewTerminalRequest(encoded: bad.encoded) == nil)
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/bash"])
    func codexsModelsAreThoseItLists(shell: String) throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        try fm.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let cache = #"{"models":[{"slug":"gpt-a","display_name":"GPT-A","visibility":"list"},"#
            + #"{"slug":"gpt-hidden","display_name":"Hidden","visibility":"hide"},{"slug":"gpt-b","display_name":"GPT-B","visibility":"list"}]}"#
        try cache.write(to: home.appendingPathComponent(".codex/models_cache.json"), atomically: true, encoding: .utf8)
        let command = TmuxRemote.agentModelsCommand(.codex)
        let listed = try run(command, in: shell, home: home)
        #expect(listed.status == 0)
        let models = [AgentModel(id: "gpt-a", name: "GPT-A"), AgentModel(id: "gpt-b", name: "GPT-B")]
        // No model in its config: its first.
        #expect(TmuxRemote.parseAgentModels(listed.output, for: .codex) == AgentModelList(models: models, defaultModel: models[0]))
        // The config's top-level model; not one in a section below.
        try "model = \"gpt-b\"\n[profiles.x]\nmodel = \"gpt-a\"\n".write(
            to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        let configured = try run(command, in: shell, home: home)
        #expect(TmuxRemote.parseAgentModels(configured.output, for: .codex).defaultModel == models[1])
        try "[profiles.x]\nmodel = \"gpt-b\"\n".write(
            to: home.appendingPathComponent(".codex/config.toml"), atomically: true, encoding: .utf8)
        let sectionOnly = try run(command, in: shell, home: home)
        #expect(TmuxRemote.parseAgentModels(sectionOnly.output, for: .codex).defaultModel == models[0])
        // No Codex here: no models, not a failure.
        try fm.removeItem(at: home.appendingPathComponent(".codex"))
        let none = try run(command, in: shell, home: home)
        #expect(none.status == 0 && TmuxRemote.parseAgentModels(none.output, for: .codex).models.isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/bash"])
    func claudesModelsAreThoseInItsNewestCatalog(shell: String) throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("claude-models-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let catalogs = home.appendingPathComponent(".claude/cache/model-catalog")
        try fm.createDirectory(at: catalogs, withIntermediateDirectories: true)
        func catalog(_ file: String, _ models: [(String, String)], age: TimeInterval) throws {
            let list = models.map { #"{"id":"\#($0.0)","name":"\#($0.1)","section":"main"}"# }.joined(separator: ",")
            let url = catalogs.appendingPathComponent(file)
            try #"{"catalog":{"config":{"models":[\#(list)]},"state":{"model":"claude-opus-4-8"}}}"#.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        try catalog("org-acct-cc.json", [("claude-opus-5-5", "Opus 5.5"), ("claude-opus-4-8", "Opus 4.8")], age: 0)
        try catalog("old-acct-cc.json", [("claude-old", "Old")], age: 3600)
        // The desktop app's: not Claude Code's.
        try catalog("org-acct-ccd.json", [("claude-desktop", "Desktop")], age: -60)
        let command = TmuxRemote.agentModelsCommand(.claude)
        let listed = try run(command, in: shell, home: home)
        #expect(listed.status == 0)
        let models = [AgentModel(id: "claude-opus-5-5", name: "Opus 5.5"), AgentModel(id: "claude-opus-4-8", name: "Opus 4.8")]
        // Its default: the catalog's own pick.
        #expect(TmuxRemote.parseAgentModels(listed.output, for: .claude) == AgentModelList(models: models, defaultModel: models[1]))
        // No word on it: none (not the first, as for Codex).
        #expect(TmuxRemote.parseAgentModels("claude-x\tX\n", for: .claude).defaultModel == nil)
        try fm.removeItem(at: catalogs)
        let none = try run(command, in: shell, home: home)
        #expect(none.status == 0 && none.output.isEmpty)
        #expect(!TerminalAgent.claude.fallbackModels.isEmpty)
    }

    @Test func badRequestsAreRefused() {
        func encoded(_ id: String, _ folder: String, _ branch: String?) -> String {
            NewTerminalRequest(folder: folder, branch: branch, agent: nil, id: id).encoded
        }
        #expect(NewTerminalRequest(encoded: encoded("0123456789ab", "relative/x", nil)) == nil)
        #expect(NewTerminalRequest(encoded: encoded("0123456789ab", "/x", "bad name")) == nil)
        #expect(NewTerminalRequest(encoded: encoded("../../etc", "/x", nil)) == nil)
        #expect(NewTerminalRequest(encoded: "not json") == nil)
        #expect(NewTerminalRequest(encoded: encoded("0123456789ab", "/x", nil)) != nil)
    }

    @Test func answers() {
        #expect(NewTerminalAnswer("$12\n") == .made(sessionID: "$12"))
        #expect(NewTerminalAnswer("!Branch exists") == .failed("Branch exists"))
        #expect(NewTerminalAnswer("") == nil)
        #expect(NewTerminalAnswer("12") == nil)
        #expect(NewTerminalAnswer.failed("a\nb").encoded == "!a b")
        #expect(NewTerminalAnswer(NewTerminalAnswer.made(sessionID: "$3").encoded) == .made(sessionID: "$3"))
    }

    @Test func branchNamesAsGitTakesThem() {
        for good in ["login", "feature/login", "fix-123", "v1.2", "lawrence/stay_awake"] {
            #expect(BranchName.isValid(good), "\(good)")
        }
        for bad in ["", "-x", "/x", "x/", "x.", "x.lock", "a..b", "a//b", "a b", "a~b", "a^b", "a:b", "a?b", "a*b",
                    "a[b", "a\\b", "a@{b", "@", "a/.b", ".a", "a\u{7}b"] {
            #expect(!BranchName.isValid(bad), "\(bad)")
        }
        #expect(BranchName.folderName("feature/login") == "feature-login")
    }

    /// Runs `command` as the Mac's login shell `shell` would, with `home`.
    private func run(_ command: String, in shell: String, home: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The phone's commands run in the Mac's login shell, often zsh.
    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/bash"])
    func aFolderListsItsFoldersAndWhichAreRepos(shell: String) throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("folders-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        for folder in ["code/lostty/.git", "code/my proj/.git", "code/notes/deep/.git", "code/.hidden/.git", "code/Api/.git"] {
            try fm.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        // A worktree's .git is a file; a file isn't a folder.
        try fm.createDirectory(at: home.appendingPathComponent("code/wt"), withIntermediateDirectories: true)
        try "gitdir: x".write(to: home.appendingPathComponent("code/wt/.git"), atomically: true, encoding: .utf8)
        try "x".write(to: home.appendingPathComponent("code/README"), atomically: true, encoding: .utf8)
        // A link to a folder is followed.
        try fm.createSymbolicLink(at: home.appendingPathComponent("code/linked"), withDestinationURL: home.appendingPathComponent("code/lostty"))

        let code = try run(TmuxRemote.folderCommand(path: home.path + "/code"), in: shell, home: home)
        #expect(code.status == 0)
        let folder = try #require(TmuxRemote.parseFolder(code.output))
        #expect(folder.path == home.path + "/code")
        #expect(!folder.isRepo)
        #expect(folder.folders == [
            .init(name: "Api", isRepo: true), .init(name: "linked", isRepo: true), .init(name: "lostty", isRepo: true),
            .init(name: "my proj", isRepo: true), .init(name: "notes", isRepo: false), .init(name: "wt", isRepo: true),
        ])
        #expect(folder.path(of: "lostty") == home.path + "/code/lostty")

        let repo = try #require(TmuxRemote.parseFolder(try run(TmuxRemote.folderCommand(path: home.path + "/code/lostty"), in: shell, home: home).output))
        #expect(repo.isRepo && repo.folders.isEmpty)
        // nil: the home folder.
        let top = try #require(TmuxRemote.parseFolder(try run(TmuxRemote.folderCommand(path: nil), in: shell, home: home).output))
        #expect(top.path == home.path && top.folders == [.init(name: "code", isRepo: false)])
        #expect(try run(TmuxRemote.folderCommand(path: home.path + "/gone"), in: shell, home: home).status == 3)
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/bash"])
    func aSearchFindsFoldersShallowestFirst(shell: String) throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("search-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: home) }
        for folder in ["lost-notes", "code/lostty/.git", "code/lostty/LostSub", "code/node_modules/lostpkg", "code/.hidden/lostx",
                       "Library/lostlib", "Lostty.app/Contents", "a/b/c/d/lostdeep", "code/other"] {
            try fm.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        func search(_ path: String?, _ keyword: String) throws -> FolderSearch? {
            let command = try #require(TmuxRemote.searchFoldersCommand(in: path, matching: keyword))
            let ran = try run(command, in: shell, home: home)
            #expect(ran.status == 0)
            return TmuxRemote.parseFolderSearch(ran.output)
        }
        // Hidden folders, node_modules, Library, app bundles, and deeper
        // than searchDepth are left out; case doesn't matter.
        let found = try #require(try search(nil, "LoSt"))
        #expect(found.path == home.path)
        #expect(found.hits == [
            .init(path: home.path + "/lost-notes", isRepo: false, depth: 1),
            .init(path: home.path + "/code/lostty", isRepo: true, depth: 2),
            .init(path: home.path + "/code/lostty/LostSub", isRepo: false, depth: 3),
        ])
        // Under a typed "~/" path; find's wildcards are plain text.
        let code = try #require(try search("~/code", "lo*st"))
        #expect(code.path == home.path + "/code")
        #expect(code.hits.map(\.name) == ["lostty", "LostSub"])
        #expect(try search(home.path + "/code", "nothing-like-it")?.hits == [])
        #expect(try run(try #require(TmuxRemote.searchFoldersCommand(in: home.path + "/gone", matching: "x")), in: shell, home: home).status == 3)
        // A typed "~/" path opens too.
        let typed = try #require(TmuxRemote.parseFolder(try run(TmuxRemote.folderCommand(path: "~/code"), in: shell, home: home).output))
        #expect(typed.path == home.path + "/code")
    }

    @Test func aSearchNeedsSomethingToLookFor() {
        #expect(TmuxRemote.searchFoldersCommand(in: nil, matching: "  ") == nil)
        #expect(TmuxRemote.searchFoldersCommand(in: nil, matching: "*?") == nil)
        #expect(TmuxRemote.parseFolderSearch("") == nil)
        #expect(TmuxRemote.parseFolderSearch("/u\nR ./a\nX ./b\nD ./.c\nD ./d/e\n")
            == FolderSearch(path: "/u", hits: [.init(path: "/u/a", isRepo: true, depth: 1), .init(path: "/u/d/e", isRepo: false, depth: 2)]))
    }

    @Test func folderOutputThatIsntOneIsNil() {
        #expect(TmuxRemote.parseFolder("") == nil)
        #expect(TmuxRemote.parseFolder("relative\n#folders\n#repos\n") == nil)
        #expect(TmuxRemote.parseFolder("/\n#folders\n./Users\n#repos\n") == MacFolder(path: "/", isRepo: false, folders: [.init(name: "Users", isRepo: false)]))
        #expect(MacFolder(path: "/", isRepo: false, folders: []).path(of: "Users") == "/Users")
    }

    @Test func theCommandsQuoteWhatTheyCarry() {
        let request = NewTerminalRequest(folder: "/Users/me/it's", branch: nil, agent: nil, id: "0123456789ab")
        let command = TmuxRemote.requestNewTerminalCommand(request)
        #expect(command.contains("set-option -g '@lostty_new_0123456789ab' '{"))
        #expect(command.contains(#"it'\''s"#))
        #expect(command.hasSuffix("wait-for -S lostty-changed"))
        #expect(TmuxRemote.newTerminalAnswerCommand(id: "0123456789ab").hasSuffix("show-options -gqv '@lostty_made_0123456789ab'"))
    }
}
