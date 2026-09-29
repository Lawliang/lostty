#if os(macOS)
import Foundation

enum SkinSource: Hashable {
    case configured(String)
    case auto(repoName: String)
    case none
}

/// Maps a working directory to where its skin comes from.
struct ProjectResolver {
    var matches: [SkinMatch]
    var auto: Bool
    var home: String = NSHomeDirectory()

    func resolve(pwd: String) -> SkinSource {
        let dir = Self.canonical(pwd)
        // APFS is (usually) case-insensitive, so match paths case-insensitively;
        // the repo name returned below still uses the on-disk/original case.
        let dirKey = dir.lowercased()
        var best: (skin: String, length: Int)?
        for match in matches {
            let path = Self.canonical(match.path)
            let pathKey = path.lowercased()
            guard dirKey == pathKey || dirKey.hasPrefix(pathKey + "/") else { continue }
            if pathKey.count > (best?.length ?? -1) { best = (match.skin, pathKey.count) }
        }
        if let best { return .configured(best.skin) }

        // A home directory under git (dotfiles) is not a project.
        guard auto, let root = Self.gitRoot(of: dir),
              root.lowercased() != Self.canonical(home).lowercased() else { return .none }
        return .auto(repoName: (root as NSString).lastPathComponent)
    }

    /// Absolute path with symlinks, `.`, `..` and trailing slashes resolved.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Nearest ancestor (including `dir`) containing a `.git` file or directory.
    static func gitRoot(of dir: String) -> String? {
        var current = dir
        while true {
            if FileManager.default.fileExists(atPath: current + "/.git") { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }
}
#endif
