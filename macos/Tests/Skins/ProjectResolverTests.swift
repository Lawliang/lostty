#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ProjectResolverTests {
    /// Builds a throwaway tree and returns its canonical root.
    private func makeTree(rootIsGitRepo: Bool = false) throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("skins-resolver-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        let root = ProjectResolver.canonical(base)
        for dir in ["projectrepos/arca/app", "projectrepos/arca-labs/site", "projectrepos/Milo/src", "plain/dir"] {
            try FileManager.default.createDirectory(atPath: "\(root)/\(dir)", withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(atPath: "\(root)/projectrepos/arca/.git", withIntermediateDirectories: true)
        // A `.git` *file* (worktrees, submodules) also marks a repo root.
        FileManager.default.createFile(atPath: "\(root)/projectrepos/Milo/.git", contents: Data())
        try FileManager.default.createSymbolicLink(
            atPath: "\(root)/link-to-arca", withDestinationPath: "\(root)/projectrepos/arca")
        if rootIsGitRepo {
            try FileManager.default.createDirectory(atPath: "\(root)/.git", withIntermediateDirectories: true)
        }
        return root
    }

    @Test func configuredMatchWinsAndRespectsComponentBoundaries() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
            SkinMatch(path: "\(root)/projectrepos/arca-labs", skin: "labs"),
        ], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca-labs/site") == .configured("labs"))
    }

    @Test func longestMatchWins() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos", skin: "generic"),
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
        ], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/Milo") == .configured("generic"))
    }

    @Test func symlinksDotsAndTrailingSlashes() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
        ], auto: false, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/link-to-arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app/../app/") == .configured("arca"))
    }

    @Test func autoSkinsUseTheGitRootName() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/Milo/src") == .auto(repoName: "Milo"))
        #expect(resolver.resolve(pwd: "\(root)/plain/dir") == .none)
        let noAuto = ProjectResolver(matches: [], auto: false, home: "/nonexistent-home")
        #expect(noAuto.resolve(pwd: "\(root)/projectrepos/Milo/src") == .none)
    }

    @Test func homeGitRootIsIgnored() throws {
        let root = try makeTree(rootIsGitRepo: true)
        let resolver = ProjectResolver(matches: [], auto: true, home: root)
        #expect(resolver.resolve(pwd: "\(root)/plain/dir") == .none)
        #expect(resolver.resolve(pwd: root) == .none)
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .auto(repoName: "arca"))
    }
}
#endif
