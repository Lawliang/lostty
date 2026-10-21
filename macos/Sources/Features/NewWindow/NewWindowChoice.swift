#if os(macOS)
import AppKit

/// ⌘N from a terminal inside a git repo asks what the new window is for,
/// since windows in one folder share its branch (switching it in one
/// switches it in all): continuing on this branch (the same folder, as
/// before), a new branch in a worktree of its own, or a new project
/// (starting at home). Outside a repo, ⌘N just opens the window.
@MainActor
enum NewWindowChoice {
    enum Choice { case continueHere, newBranch, newProject }

    /// Opens a new window starting from `config`'s folder, asking first when
    /// that folder is in a repo.
    static func newWindow(_ ghostty: Ghostty.App, config: Ghostty.SurfaceConfiguration?) {
        guard let pwd = config?.workingDirectory, let repo = NewWindowRepo.read(pwd: pwd) else {
            _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
            return
        }
        switch ask(repo) {
        case .continueHere:
            _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
        case .newProject:
            var home = config ?? Ghostty.SurfaceConfiguration()
            home.workingDirectory = NSHomeDirectory()
            _ = TerminalController.newWindow(ghostty, withBaseConfig: home)
        case .newBranch:
            guard let branch = askBranch(repo) else { return }
            Task {
                // Off the main thread: checking out a big repo takes a moment.
                let made = await Task.detached { NewWindowRepo.addWorktree(repo, branch: branch) }.value
                switch made {
                case .success(let path):
                    var there = config ?? Ghostty.SurfaceConfiguration()
                    there.workingDirectory = path
                    _ = TerminalController.newWindow(ghostty, withBaseConfig: there)
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "Couldn't make the worktree"
                    alert.informativeText = error.message
                    alert.runModal()
                }
            }
        case nil:
            return
        }
    }

    /// The question; nil when cancelled.
    private static func ask(_ repo: NewWindowRepo) -> Choice? {
        let alert = NSAlert()
        alert.messageText = "What's this window for?"
        let on = repo.branch.map { " on \($0)" } ?? ""
        alert.informativeText = "This terminal is in \(repo.name)\(on). Windows in the same folder share its "
            + "branch: switching it in one switches it in all of them."
        alert.addButton(withTitle: repo.branch.map { "Continue on \($0)" } ?? "Continue Here")
        alert.addButton(withTitle: "New Branch and Worktree…")
        alert.addButton(withTitle: "New Project")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .continueHere
        case .alertSecondButtonReturn: return .newBranch
        case .alertThirdButtonReturn: return .newProject
        default: return nil
        }
    }

    /// The new branch's name; nil when cancelled or left empty.
    private static func askBranch(_ repo: NewWindowRepo) -> String? {
        let alert = NSAlert()
        alert.messageText = "New branch in its own worktree"
        let from = repo.branch.map { "Starts from \($0), in" } ?? "Starts here, in"
        alert.informativeText = "\(from) \(repo.name)/\(NewWindowRepo.worktrees). Other windows stay on their branches."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "branch-name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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
