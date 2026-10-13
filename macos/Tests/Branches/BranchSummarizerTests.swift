#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct BranchSummarizerTests {
    /// An executable stand-in for `claude` that runs `body` after reading stdin.
    private func fakeClaude(_ body: String) throws -> String {
        let path = try TempRepo.makeDirectory() + "/claude"
        try "#!/bin/sh\ncat > /dev/null\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func branchRepo() throws -> TempRepo {
        let repo = try TempRepo.make()
        try repo.git("checkout", "-q", "-b", "feat")
        try repo.commit("feat one")
        return repo
    }

    @Test func returnsWhatClaudePrints() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo 'Adds feat one.'")
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .success("Adds feat one."))
    }

    @Test func thePromptIsPlainWhateverTheGitConfig() throws {
        let repo = try branchRepo()
        let tool = try TempRepo.makeDirectory() + "/difftool"
        try "#!/bin/sh\necho EXTERNAL-DIFF\n".write(toFile: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
        try repo.git("config", "diff.external", tool)
        try repo.git("config", "color.ui", "always")
        // This claude prints the prompt it was given.
        let claude = try TempRepo.makeDirectory() + "/claude"
        try "#!/bin/sh\ncat\n".write(toFile: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude)

        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        let prompt = try result.get()
        #expect(prompt.contains("+feat one"))
        #expect(!prompt.contains("EXTERNAL-DIFF"))
        #expect(!prompt.contains("\u{1B}["))
    }

    @Test func reportsClaudesError() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo 'Not logged in' >&2; exit 1")
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .failure(.failed("Not logged in")))
    }

    @Test func aMissingBranchIsAGitError() throws {
        let repo = try branchRepo()
        let claude = try fakeClaude("echo never")
        let result = BranchSummarizer.run(branch: "nope", base: "main", root: repo.root, claude: claude, handle: RunHandle())
        #expect(result == .failure(.git))
    }

    @Test func cancelKillsTheRun() throws {
        let repo = try branchRepo()
        // exec: the pid Cancel kills is sleep itself, so nothing keeps the pipes open.
        let claude = try fakeClaude("exec sleep 10")
        let handle = RunHandle()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { handle.cancel() }
        let start = Date()
        let result = BranchSummarizer.run(branch: "feat", base: "main", root: repo.root, claude: claude, handle: handle)
        #expect(result == .failure(.cancelled))
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
#endif
