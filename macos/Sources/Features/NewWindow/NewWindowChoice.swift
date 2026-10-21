#if os(macOS)
import AppKit

/// ⌘N from a terminal inside a git repo opens the window at once, asking
/// over it what it's for (`NewWindowPrompt`), since windows in one folder
/// share its branch (switching it in one switches it in all): continuing
/// on this branch (the same folder, as before), a new branch in a worktree
/// of its own, or a new project (starting at home). Outside a repo, ⌘N
/// just opens the window.
@MainActor
enum NewWindowChoice {
    static func newWindow(_ ghostty: Ghostty.App, config: Ghostty.SurfaceConfiguration?) {
        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
        guard let pwd = config?.workingDirectory, let repo = NewWindowRepo.read(pwd: pwd),
              let window = controller.window as? TerminalWindow else { return }
        let sidebar = window.extensionSidebarModel
        sidebar.newWindowPrompt = NewWindowPrompt(repo: repo, window: window) { [weak controller, weak sidebar] folder in
            sidebar?.newWindowPrompt = nil
            guard let controller else { return }
            if let folder {
                restart(controller, in: folder, config: config)
            } else if let surface = controller.focusedSurface {
                Ghostty.moveFocus(to: surface)
            }
        }
    }

    /// The window's terminal starts over in `folder`; the first one's shell
    /// (and its tmux session) ends.
    private static func restart(_ controller: TerminalController, in folder: String, config: Ghostty.SurfaceConfiguration?) {
        guard let app = controller.ghostty.app else { return }
        var there = config ?? Ghostty.SurfaceConfiguration()
        there.workingDirectory = folder
        let surface = Ghostty.SurfaceView(app, baseConfig: there)
        let old = Array(controller.surfaceTree)
        controller.surfaceTree = .init(view: surface)
        controller.focusedSurface = surface
        DispatchQueue.main.async { Ghostty.moveFocus(to: surface) }
        // The engine may still message the first terminal (its pointer, its
        // title) until its surface is freed, and it messages it through the
        // view: free the surface first, and the view once that's done.
        for view in old { view.releaseSurface() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { withExtendedLifetime(old) {} }
    }
}

/// The repo a terminal is in, as the new-window question needs it.
struct NewWindowRepo: Equatable {
    /// Where new worktrees go, under the main checkout.
    static let worktrees = ".claude/worktrees"

    /// The main checkout's folder.
    let root: String
    /// The checkout the terminal is in: the main one or a worktree.
    let checkout: String
    /// The repo's git folder, shared by every checkout.
    let commonDir: String
    /// nil when detached.
    let branch: String?

    var name: String { (root as NSString).lastPathComponent }

    struct Failure: Error, Equatable { let message: String }

    /// The repo at `pwd`, or nil outside one. Blocking, but quick.
    static func read(pwd: String) -> NewWindowRepo? {
        Git.run(["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir", "--abbrev-ref", "HEAD"],
                in: pwd).flatMap(parse)
    }

    /// `git rev-parse --show-toplevel --git-common-dir --abbrev-ref HEAD`'s
    /// three lines.
    static func parse(_ output: String) -> NewWindowRepo? {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count == 3 else { return nil }
        let common = (lines[1] as NSString).standardizingPath
        // A main checkout keeps its git folder at <root>/.git.
        let root = (common as NSString).lastPathComponent == ".git"
            ? (common as NSString).deletingLastPathComponent : lines[0]
        return NewWindowRepo(root: root, checkout: lines[0], commonDir: common, branch: lines[2] == "HEAD" ? nil : lines[2])
    }

    /// Where `branch`'s worktree goes: one folder, its slashes turned to dashes.
    func worktreePath(for branch: String) -> String {
        (root as NSString).appendingPathComponent(Self.worktrees + "/" + branch.replacingOccurrences(of: "/", with: "-"))
    }

    /// A worktree on `branch` (made from this checkout's HEAD if it's new),
    /// kept out of the main checkout's `git status`. Blocking.
    static func addWorktree(_ repo: NewWindowRepo, branch: String) -> Result<String, Failure> {
        guard run(["check-ref-format", "--branch", branch], in: repo.checkout).status == 0 else {
            return .failure(Failure(message: "“\(branch)” isn't a valid branch name."))
        }
        let path = repo.worktreePath(for: branch)
        guard !FileManager.default.fileExists(atPath: path) else {
            return .failure(Failure(message: "\(path) already exists."))
        }
        let exists = run(["show-ref", "--verify", "--quiet", "refs/heads/" + branch], in: repo.checkout).status == 0
        let add = run(["worktree", "add"] + (exists ? [path, branch] : ["-b", branch, path, "HEAD"]), in: repo.checkout)
        guard add.status == 0 else {
            let said = add.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Failure(message: said.isEmpty ? "git worktree add failed." : said))
        }
        excludeWorktrees(repo)
        return .success(path)
    }

    /// Adds the worktrees folder to the repo's own exclude file (never a
    /// tracked .gitignore) unless something already ignores it.
    private static func excludeWorktrees(_ repo: NewWindowRepo) {
        guard run(["check-ignore", "-q", worktrees + "/"], in: repo.root).status != 0 else { return }
        let info = (repo.commonDir as NSString).appendingPathComponent("info")
        try? FileManager.default.createDirectory(atPath: info, withIntermediateDirectories: true)
        let exclude = (info as NSString).appendingPathComponent("exclude")
        let current = (try? String(contentsOfFile: exclude, encoding: .utf8)) ?? ""
        let line = "/" + worktrees + "/\n"
        let text = current + (current.isEmpty || current.hasSuffix("\n") ? "" : "\n") + line
        try? text.write(toFile: exclude, atomically: true, encoding: .utf8)
    }

    private static func run(_ args: [String], in dir: String) -> ProcessResult {
        ProcessRunner.run(Git.executable, ["-C", dir] + args, environment: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"],
                          timeout: 60)
            ?? ProcessResult(status: -1, stdout: "", stderr: "git didn't finish.")
    }
}
#endif
