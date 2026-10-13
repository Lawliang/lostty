#if os(macOS)
import Foundation
@testable import Lostty

enum TempRepoError: Error {
    case failed(String)
}

/// Throwaway git repos for tests, with a fixed identity and no user config.
struct TempRepo {
    let root: String

    /// A new empty directory under the temp dir, canonical (no /var symlink).
    static func makeDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("branches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ProjectResolver.canonical(url.path)
    }

    /// A repo at `<new dir>/repo` on `main` with one commit, "first".
    static func make(firstCommit date: Date = Date()) throws -> TempRepo {
        let repo = TempRepo(root: try makeDirectory() + "/repo")
        try FileManager.default.createDirectory(atPath: repo.root, withIntermediateDirectories: true)
        try repo.git("init", "-q", "-b", "main")
        try repo.commit("first", date: date)
        return repo
    }

    /// Runs git in `dir` (default: the repo root); throws on failure.
    @discardableResult
    func git(_ args: String..., in dir: String? = nil, date: Date = Date()) throws -> String {
        let stamp = "\(Int(date.timeIntervalSince1970)) +0000"
        let env = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
            "GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp,
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        ]
        guard let result = ProcessRunner.run(
            Git.executable, ["-C", dir ?? root] + args, environment: env, timeout: 10),
            result.status == 0
        else { throw TempRepoError.failed(args.joined(separator: " ")) }
        return result.stdout
    }

    /// Adds a file named after `message` and commits it.
    func commit(_ message: String, in dir: String? = nil, date: Date = Date()) throws {
        let directory = dir ?? root
        let file = message.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        FileManager.default.createFile(atPath: "\(directory)/\(file).txt", contents: Data(message.utf8))
        try git("add", "-A", in: directory, date: date)
        try git("commit", "-q", "-m", message, in: directory, date: date)
    }
}
#endif
