#if os(macOS)
import AppKit

/// ⌘N from a terminal inside a git repo opens the window at once, asking
/// over it what it's for (`NewWindowPrompt`), since windows in one folder
/// share its branch (switching it in one switches it in all): continuing
/// on this branch (the same folder, as before), a new branch in a worktree
/// of its own, or a new project (starting at home). Outside a repo, ⌘N
/// just opens the window. On the canvas, ⌘N and ⌘T ask the same over the
/// new card, and a card outside any repo (a zone with no folder) asks
/// which project.
@MainActor
enum NewWindowChoice {
    static func newWindow(_ ghostty: Ghostty.App, config: Ghostty.SurfaceConfiguration?) {
        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
        guard let window = controller.window as? TerminalWindow else { return }
        ask(controller, sidebar: window.extensionSidebarModel, config: config, noun: "window")
    }

    /// A new card asks while it's the canvas's focused card: the canvas's
    /// other cards share its window and its keys.
    static func ask(_ card: CardController, config: Ghostty.SurfaceConfiguration?) {
        // In a project's zone: a worktree of that project, at once. Started
        // at home (a zone with no folder): which project, then a worktree.
        let canvas = card.canvas
        let zones = canvas.map { canvas in canvas.model.zones.compactMap { canvas.model.startFolder(ofZone: $0.id) } } ?? []
        let project = canvas?.model.card(card.id).flatMap { canvas?.model.zone(for: $0.frame) }
            .flatMap { canvas?.model.startFolder(ofZone: $0) }.flatMap(NewWindowRepo.read(pwd:))
        let projects = config?.workingDirectory == NSHomeDirectory() ? NewWindowProject.folder(near: zones) : nil
        ask(card, sidebar: card.sidebar, config: config, noun: "card", repo: project, projectsIn: projects,
            worktreeAtOnce: project != nil || projects != nil) { [weak card] in
            guard let card else { return false }
            return card.canvas?.focusedCard === card
        }
    }

    private static func ask(
        _ controller: BaseTerminalController, sidebar: ExtensionSidebarModel, config: Ghostty.SurfaceConfiguration?,
        noun: String, repo zoneRepo: NewWindowRepo? = nil, projectsIn projects: String? = nil,
        worktreeAtOnce: Bool = false, takesKeys: @escaping () -> Bool = { true }
    ) {
        let repo = zoneRepo ?? config?.workingDirectory.flatMap(NewWindowRepo.read(pwd:))
        guard repo != nil || projects != nil, let window = controller.window else { return }
        sidebar.newWindowPrompt = NewWindowPrompt(
            repo: repo, projectsIn: projects, worktreeAtOnce: worktreeAtOnce, window: window, noun: noun,
            takesKeys: takesKeys
        ) {
            [weak controller, weak sidebar] folder in
            let worktree = sidebar?.newWindowPrompt?.madeWorktree == true
            sidebar?.newWindowPrompt = nil
            guard let controller else { return }
            if let folder {
                let surface = restart(controller, in: folder, config: config)
                // A new worktree is for new work: Claude starts in it.
                if worktree, let surface { SessionRestore.type("claude", into: surface.id) }
            } else if let surface = controller.focusedSurface {
                Ghostty.moveFocus(to: surface)
            }
        }
    }

    /// The window's or card's terminal starts over in `folder`; the first
    /// one's shell (and its tmux session) ends.
    @discardableResult
    private static func restart(
        _ controller: BaseTerminalController, in folder: String, config: Ghostty.SurfaceConfiguration?
    ) -> Ghostty.SurfaceView? {
        guard let app = controller.ghostty.app else { return nil }
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
        return surface
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

    /// A worktree on the first free placeholder branch, `wt-1`, `wt-2`…,
    /// started from the repo's default branch as just fetched (never what
    /// the main checkout has out), marked as Lostty's to rename:
    /// `branch.<name>.lostty-base` holds the commit it starts from, and
    /// `lostty +ticket working` names it after the feature until something
    /// merges it. Blocking.
    static func addPlaceholderWorktree(_ repo: NewWindowRepo) -> Result<String, Failure> {
        let taken = { (name: String) in
            run(["show-ref", "--verify", "--quiet", "refs/heads/" + name], in: repo.checkout).status == 0
                || FileManager.default.fileExists(atPath: repo.worktreePath(for: name))
        }
        guard let name = (1...999).lazy.map({ "wt-\($0)" }).first(where: { !taken($0) }) else {
            return .failure(Failure(message: "No free worktree name."))
        }
        return WorktreeMaker.make(branch: name, in: repo.checkout).mapError { Failure(message: $0.message) }.map { path in
            let base = run(["rev-parse", "HEAD"], in: path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = run(["config", "branch.\(name).lostty-base", base], in: path)
            return path
        }
    }

    private static func run(_ args: [String], in dir: String) -> ProcessResult {
        ProcessRunner.run(Git.executable, ["-C", dir] + args, environment: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"],
                          timeout: 60)
            ?? ProcessResult(status: -1, stdout: "", stderr: "git didn't finish.")
    }
}
#endif
