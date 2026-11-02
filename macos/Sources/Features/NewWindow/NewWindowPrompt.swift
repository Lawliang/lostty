#if os(macOS)
import AppKit
import SwiftUI

/// The question over a new window or canvas card from a repo: what's it
/// for? Its keys are the question's while it shows (1, 2, 3, Return for a
/// new worktree, Esc to go back or continue), so typing never reaches the
/// terminal under it; ⌘ shortcuts still work. 3 lists the other projects
/// beside this one: picking a repo asks the same about it. A terminal
/// outside any repo (a zone with no folder) starts on that list.
@MainActor
final class NewWindowPrompt: ObservableObject, Identifiable {
    enum Stage: Equatable { case choosing, projects, working }

    /// The repo the choices are about: the terminal's, or a project picked;
    /// nil until one is picked when the terminal isn't in a repo.
    @Published private(set) var repo: NewWindowRepo?
    /// The terminal's repo.
    private let start: NewWindowRepo?
    /// The folder whose repos 3 lists.
    private let projectsFolder: String
    /// The projects 3 lists, and the filter typed over them.
    private(set) var projects: [NewWindowProject] = []
    @Published var query = "" { didSet { selected = 0 } }
    @Published private(set) var selected = 0
    /// "window" or "card".
    let noun: String
    @Published private(set) var stage: Stage = .choosing
    /// Whether the answer was a new worktree: its terminal starts Claude.
    private(set) var madeWorktree = false
    /// A canvas card in a project's zone asks nothing: it makes a worktree
    /// at once, and with no project yet, once one is picked.
    let worktreeAtOnce: Bool
    @Published private(set) var error: String?
    /// Ends the question: the folder to start the terminal over in, or nil
    /// to keep it.
    private let finish: (String?) -> Void
    private weak var window: NSWindow?
    /// Whether the question takes the window's keys now: a card's only
    /// while it's the focused card.
    private let takesKeys: () -> Bool
    nonisolated(unsafe) private var monitor: Any?

    init(
        repo: NewWindowRepo?, projectsIn folder: String? = nil, worktreeAtOnce: Bool = false, window: NSWindow,
        noun: String = "window", takesKeys: @escaping () -> Bool = { true }, finish: @escaping (String?) -> Void
    ) {
        self.worktreeAtOnce = worktreeAtOnce
        self.repo = repo
        self.start = repo
        projectsFolder = repo.map { ($0.root as NSString).deletingLastPathComponent } ?? folder ?? NSHomeDirectory()
        self.noun = noun
        self.window = window
        self.takesKeys = takesKeys
        self.finish = finish
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.take(event) ? nil : event
        }
        if repo == nil { pickProject() } else if worktreeAtOnce { newWorktree() }
    }

    /// Whether the question took a key pressed in its window.
    func take(_ event: NSEvent) -> Bool {
        guard event.window === window, takesKeys() else { return false }
        return key(event)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Whether the choices are about a project picked with 3.
    var picked: Bool { repo?.checkout != start?.checkout }

    /// On in the picked repo's main folder, or where the terminal is.
    func continueHere() { done(picked ? repo?.checkout : nil) }

    func pickProject() {
        error = nil
        projects = NewWindowProject.list(in: projectsFolder, leaving: start?.root)
        query = ""
        stage = .projects
    }

    /// The projects whose names hold what's typed.
    var shown: [NewWindowProject] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? projects : projects.filter { $0.name.localizedCaseInsensitiveContains(typed) }
    }

    /// A repo asks what the terminal is for there; anything else starts it there.
    func choose(_ project: NewWindowProject) {
        guard let picked = NewWindowRepo.read(pwd: project.path) else { return done(project.path) }
        repo = picked
        stage = .choosing
        if worktreeAtOnce { newWorktree() }
    }

    func chooseSelected() {
        let list = shown
        if list.indices.contains(selected) { choose(list[selected]) }
    }

    /// Back to the choices; with no repo to choose about, the terminal
    /// stays where it is.
    func back() {
        if repo == nil { done(nil) } else { stage = .choosing }
    }

    /// Makes a worktree on a placeholder branch (`wt-3`), then starts the
    /// terminal there; the branch takes the feature's name when its agent
    /// runs `+ticket working`. An error stays on the card.
    func newWorktree() {
        guard stage == .choosing, let repo else { return }
        error = nil
        stage = .working
        Task {
            // Off the main thread: checking out a big repo takes a moment.
            let made = await Task.detached { NewWindowRepo.addPlaceholderWorktree(repo) }.value
            switch made {
            case .success(let path):
                madeWorktree = true
                done(path)
            case .failure(let failure):
                error = failure.message
                stage = .choosing
            }
        }
    }

    private func done(_ folder: String?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish(folder)
    }

    /// Whether the card took `event`.
    private func key(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        let escape = event.keyCode == 53
        switch stage {
        case .projects:
            // The filter field types and Return picks; arrows move, Esc goes back.
            switch event.keyCode {
            case 125: selected = min(selected + 1, max(shown.count - 1, 0))
            case 126: selected = max(selected - 1, 0)
            case 53: back()
            default: return false
            }
            return true
        case .choosing:
            switch event.charactersIgnoringModifiers {
            case "1": continueHere()
            case "2", "\r": newWorktree()
            case "3": pickProject()
            default: if escape { continueHere() }
            }
            return true
        case .working:
            return true
        }
    }
}

/// The new window's question, over everything in it.
struct NewWindowPromptOverlay: View {
    @ObservedObject var sidebar: ExtensionSidebarModel

    var body: some View {
        if let prompt = sidebar.newWindowPrompt {
            ZStack {
                Color.black.opacity(0.35)
                NewWindowPromptCard(prompt: prompt, chrome: sidebar.chromeColor ?? .windowBackgroundColor)
            }
            .transition(.opacity)
        }
    }
}

private struct NewWindowPromptCard: View {
    @ObservedObject var prompt: NewWindowPrompt
    let chrome: NSColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let repo = prompt.repo, prompt.stage == .working, prompt.worktreeAtOnce {
                making(repo)
            } else if let repo = prompt.repo, prompt.stage != .projects {
                choosing(repo)
            } else {
                NewWindowProjectList(prompt: prompt)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: chrome)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .environment(\.colorScheme, chrome.isLightColor ? .light : .dark)
        .padding(16)
    }

    /// A project zone's card while its worktree is made.
    private func making(_ repo: NewWindowRepo) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            header("New worktree in \(repo.name)", "From its main branch, as just fetched. Claude starts in it.")
        }
    }

    private func choosing(_ repo: NewWindowRepo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header("What's this \(prompt.noun) for?",
                   "In \(repo.name)\(repo.branch.map { " on \($0)" } ?? ""). \(prompt.noun.capitalized)s in one folder "
                    + "share its branch: switching it in one switches it in all of them.")
            VStack(spacing: 4) {
                row("1", "arrow.turn.down.right", repo.branch.map { "Continue on \($0)" } ?? "Continue here",
                    prompt.picked ? "The project's main folder." : "The same folder as your other \(prompt.noun)s.",
                    prompt.continueHere)
                row("2 ↩", "arrow.triangle.branch", "Same project but new branch/worktree",
                    "Its own folder and branch, named once the work has a name.", prompt.newWorktree)
                row("3", "folder.badge.plus", "Another project", "Pick one of your projects, or your home folder.",
                    prompt.pickProject)
            }
            .disabled(prompt.stage == .working)
            if prompt.stage == .working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Making the worktree…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let error = prompt.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.95, green: 0.33, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(
        _ key: String, _ symbol: String, _ title: String, _ detail: String, _ action: @escaping () -> Void
    ) -> some View {
        NewWindowPromptRow(key: key, symbol: symbol, title: title, detail: detail, action: action)
    }
}

/// One choice: lit on hover, its number key at the right.
private struct NewWindowPromptRow: View {
    let key: String
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(key)
                    .font(ClaudeUsageFont.font(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, key.count > 1 ? 5 : 0)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
#endif
