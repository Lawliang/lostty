#if os(macOS)
import LosttyRemote
import SwiftUI

/// The focused pane's repo and branch, as the phone's rows say them:
/// "lostty/skins", or "lostty" on a detached HEAD.
struct ProjectLabel: Equatable, Sendable {
    var project: String
    var branch: String?

    var text: String {
        branch.map { "\(project)/\($0)" } ?? project
    }

    /// The repo `pwd` is in, read from `.git` and `HEAD` the way the phone's
    /// listing does (`TmuxRemote.listScript`): no git process, so it is
    /// cheap to poll. A worktree is named for its repo, not its own folder.
    /// nil outside a repo, and for a repo at the home folder (dotfiles), as
    /// for skins. Blocking file reads: call it off the main thread.
    static func read(pwd: String, home: String = NSHomeDirectory()) -> ProjectLabel? {
        let fm = FileManager.default
        var dir = (pwd as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        while !dir.isEmpty, dir != "/", dir != home {
            let dotGit = dir + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
                let gitDir: String
                if isDir.boolValue {
                    gitDir = dotGit
                } else {
                    // A worktree's `.git` file: "gitdir: <path>".
                    guard let line = try? String(contentsOfFile: dotGit, encoding: .utf8)
                        .split(separator: "\n").first,
                        line.hasPrefix("gitdir: ") else { return nil }
                    let path = String(line.dropFirst("gitdir: ".count))
                    gitDir = path.hasPrefix("/") ? path : dir + "/" + path
                }
                let project: String
                if let range = gitDir.range(of: "/.git/worktrees/") {
                    project = (String(gitDir[..<range.lowerBound]) as NSString).lastPathComponent
                } else {
                    project = (dir as NSString).lastPathComponent
                }
                let head = (try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                let branch = head.flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
                return ProjectLabel(project: project, branch: branch)
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}

/// At the right of the title bar: "> lostty/skins" for the focused pane, in
/// a capsule of its skin (background, text, and the accent for the ">" and
/// the edge), as its row looks in the phone's list. Hidden outside a repo.
struct ProjectPill: View {
    /// How often the branch is re-read, so a checkout shows without a `cd`.
    static let refresh: Duration = .seconds(2)

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @State private var label: ProjectLabel?

    private var pane: UUID? { model.focusedSurfaceID }
    private var pwd: String? { pane.flatMap { skins.panes[$0]?.pwd } }

    var body: some View {
        Group {
            if let label { pill(label) }
        }
        .task(id: pwd) {
            guard let pwd else {
                label = nil
                return
            }
            while !Task.isCancelled {
                let read = await Task.detached { ProjectLabel.read(pwd: pwd) }.value
                guard !Task.isCancelled else { return }
                if read != label { label = read }
                try? await Task.sleep(for: Self.refresh)
            }
        }
    }

    private func pill(_ label: ProjectLabel) -> some View {
        let colors = PillColors(skin: pane.flatMap { skins.effectiveSkin($0) }, chrome: model.chromeColor)
        return HStack(spacing: 5) {
            Text(">")
                .fontWeight(.heavy)
                .foregroundStyle(colors.prompt)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Text(label.project).foregroundStyle(colors.primary)
                if let branch = label.branch {
                    Text("/" + branch).foregroundStyle(colors.secondary)
                }
            }
            .truncationMode(.middle)
        }
        .font(ClaudeUsageFont.font(size: 11.5))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .frame(maxWidth: 280)
        .background(Capsule().fill(colors.background))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .help(pwd ?? label.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Project \(label.text)")
    }
}

/// The pill's colors: the skin's, picked as the phone's `RowColors` picks
/// a row's, else the window's title bar with a faint edge.
private struct PillColors {
    var background: Color
    var primary: Color
    var secondary: Color
    var border: Color
    var prompt: Color

    init(skin: Skin?, chrome: NSColor?) {
        guard let skin = skin?.sessionSkin() else {
            let chrome = chrome ?? .windowBackgroundColor
            let ink: Color = chrome.isLightColor ? .black : .white
            background = Color(nsColor: chrome)
            primary = ink.opacity(0.85)
            secondary = ink.opacity(0.55)
            border = ink.opacity(0.15)
            prompt = ink.opacity(0.7)
            return
        }
        // A skin without its own text color shows the terminal's default:
        // light text, or dark on a light background.
        let text = skin.foreground.map(Color.init) ?? (skin.isLight ? Color(white: 0.11) : Color(white: 0.95))
        let accent = Color(skin.accent)
        background = Color(skin.background)
        primary = text
        secondary = text.opacity(0.65)
        border = accent.opacity(0.45)
        // A made-up accent is the background lightened: too faint on a
        // light one, where the text color stands in.
        prompt = skin.isLight && skin.accent.luminance > 0.4 ? text : accent
    }
}

private extension Color {
    init(_ rgb: SessionSkin.RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
#endif
