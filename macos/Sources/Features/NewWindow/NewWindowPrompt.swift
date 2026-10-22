#if os(macOS)
import AppKit
import SwiftUI

/// The question over a new window or canvas card from a repo: what's it
/// for? Its keys are the question's while it shows (1, 2, 3, Return to continue, Esc to go
/// back or continue), so typing never reaches the terminal under it; ⌘
/// shortcuts still work.
@MainActor
final class NewWindowPrompt: ObservableObject, Identifiable {
    enum Stage: Equatable { case choosing, naming, working }

    let repo: NewWindowRepo
    /// "window" or "card".
    let noun: String
    @Published private(set) var stage: Stage = .choosing
    @Published var branch = ""
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
        repo: NewWindowRepo, window: NSWindow, noun: String = "window", takesKeys: @escaping () -> Bool = { true },
        finish: @escaping (String?) -> Void
    ) {
        self.repo = repo
        self.noun = noun
        self.window = window
        self.takesKeys = takesKeys
        self.finish = finish
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.take(event) ? nil : event
        }
    }

    /// Whether the question took a key pressed in its window.
    func take(_ event: NSEvent) -> Bool {
        guard event.window === window, takesKeys() else { return false }
        return key(event)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func continueHere() { done(nil) }
    func newProject() { done(NSHomeDirectory()) }

    func startNaming() {
        error = nil
        stage = .naming
    }

    func back() {
        error = nil
        stage = .choosing
    }

    /// Makes the worktree, then starts the terminal there; an error stays
    /// on the card.
    func create() {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stage == .naming, !name.isEmpty else { return }
        stage = .working
        let repo = repo
        Task {
            // Off the main thread: checking out a big repo takes a moment.
            let made = await Task.detached { NewWindowRepo.addWorktree(repo, branch: name) }.value
            switch made {
            case .success(let path):
                done(path)
            case .failure(let failure):
                error = failure.message
                stage = .naming
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
        case .choosing:
            switch event.charactersIgnoringModifiers {
            case "1", "\r": continueHere()
            case "2": startNaming()
            case "3": newProject()
            default: if escape { continueHere() }
            }
            return true
        case .naming:
            // The branch field types; Esc goes back.
            if escape { back() }
            return escape
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
    @FocusState private var fieldFocused: Bool

    private var repo: NewWindowRepo { prompt.repo }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch prompt.stage {
            case .choosing: choosing
            case .naming, .working: naming
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

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("What's this \(prompt.noun) for?",
                   "In \(repo.name)\(repo.branch.map { " on \($0)" } ?? ""). \(prompt.noun.capitalized)s in one folder "
                    + "share its branch: switching it in one switches it in all of them.")
            VStack(spacing: 4) {
                row("1", "arrow.turn.down.right", repo.branch.map { "Continue on \($0)" } ?? "Continue here",
                    "The same folder as your other \(prompt.noun)s.", prompt.continueHere)
                row("2", "arrow.triangle.branch", "Same project but new branch/worktree",
                    "Its own folder and branch. Other \(prompt.noun)s stay put.", prompt.startNaming)
                row("3", "folder.badge.plus", "New project", "Start in your home folder.", prompt.newProject)
            }
        }
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Same project but new branch/worktree",
                   "Starts from \(repo.branch ?? "here"), in \(repo.name)/\(NewWindowRepo.worktrees).")
            TextField("branch-name", text: $prompt.branch)
                .textFieldStyle(.roundedBorder)
                .font(ClaudeUsageFont.font(size: 13))
                .focused($fieldFocused)
                .disabled(prompt.stage == .working)
                .onSubmit { prompt.create() }
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }
            if let error = prompt.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.95, green: 0.33, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Back") { prompt.back() }
                    .disabled(prompt.stage == .working)
                Spacer()
                if prompt.stage == .working { ProgressView().controlSize(.small) }
                Button("Create") { prompt.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.stage == .working
                        || prompt.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .frame(width: 20, height: 20)
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
