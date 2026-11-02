#if os(macOS)
import AppKit
import SwiftUI

/// A project the new-window question's 3 offers: a repo beside the
/// terminal's, or the home folder.
struct NewWindowProject: Equatable {
    let name: String
    let path: String

    var isHome: Bool { path == NSHomeDirectory() }

    /// The repos in the folder holding `root` (`~/projectrepos` for
    /// `~/projectrepos/lostty`), `root` left out, the one used last first;
    /// then the home folder.
    static func list(near root: String) -> [NewWindowProject] {
        let parent = (root as NSString).deletingLastPathComponent
        let files = FileManager.default
        let repos = ((try? files.contentsOfDirectory(atPath: parent)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .map { (parent as NSString).appendingPathComponent($0) }
            .filter { $0 != root && files.fileExists(atPath: $0 + "/.git") }
            .map { (path: $0, used: lastUsed($0)) }
            .sorted { $0.used > $1.used }
            .map { NewWindowProject(name: ($0.path as NSString).lastPathComponent, path: $0.path) }
        return repos + [NewWindowProject(name: "Home folder", path: NSHomeDirectory())]
    }

    /// When git last touched the repo's index: a status, checkout or commit.
    private static func lastUsed(_ repo: String) -> Date {
        let files = FileManager.default
        for path in [repo + "/.git/index", repo + "/.git"] {
            if let date = (try? files.attributesOfItem(atPath: path))?[.modificationDate] as? Date { return date }
        }
        return .distantPast
    }
}

/// 3's list: a filter field over the projects, the selected one lit.
struct NewWindowProjectList: View {
    @ObservedObject var prompt: NewWindowPrompt
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which project?").font(.system(size: 15, weight: .semibold))
                Text("Type to filter, ↑↓ to move, Return to pick, Esc to go back.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            TextField("Filter", text: $prompt.query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { prompt.chooseSelected() }
                .onAppear { DispatchQueue.main.async { fieldFocused = true } }
            let shown = prompt.shown
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.path) { index, project in
                            row(project, lit: index == prompt.selected).id(project.path)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: prompt.selected) { _, selected in
                    if shown.indices.contains(selected) { proxy.scrollTo(shown[selected].path) }
                }
            }
            if shown.isEmpty {
                Text("No project matches.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ project: NewWindowProject, lit: Bool) -> some View {
        Button { prompt.choose(project) } label: {
            HStack(spacing: 10) {
                Image(systemName: project.isHome ? "house" : "folder")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.system(size: 13, weight: .medium))
                    Text((project.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(lit ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
