#if os(macOS)
import SwiftUI

/// The Branches app, inside the widened sidebar.
struct BranchesPanel: View {
    @ObservedObject var model: BranchesModel
    let onClose: () -> Void
    @State private var showOlder = false

    var body: some View {
        VStack(spacing: 0) {
            BranchesHeader(
                title: model.snapshot?.name ?? "Branches",
                subtitle: model.snapshot?.base.map { "base \($0)" },
                busy: model.refreshing && model.status == .loaded,
                onClose: onClose)
            GuardApprovalsSection()
            Divider().overlay(LosttyTheme.hairline)
            content
        }
        .modifier(PanelEscape(onClose: onClose))
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .closed, .loading:
            centered { ProgressView().controlSize(.small) }
        case .noPane:
            centered { note("Click a pane, then open Branches.") }
        case .notARepo:
            centered { note("This pane isn't in a git repo.") }
        case .failed:
            centered {
                VStack(spacing: 8) {
                    note("Couldn't read this repo.")
                    Button("Retry") { Task { await model.reload() } }
                }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if model.refreshFailed {
                    Text("Couldn't refresh")
                        .font(.system(size: 11))
                        .foregroundStyle(LosttyTheme.warning)
                        .padding(.horizontal, 12)
                }
                group("Active", model.sections.active)
                ForEach(model.sections.detached) { detached in
                    sectionTitle("Detached @ \(detached.sha)")
                    ForEach(detached.sessions) { SessionLine(session: $0) }
                }
                group("Branches", model.sections.recent)
                if !model.sections.older.isEmpty {
                    Button { showOlder.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showOlder ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Older (\(model.sections.older.count))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    if showOlder {
                        ForEach(model.sections.older) { BranchRowView(row: $0, model: model) }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [BranchRow]) -> some View {
        if !rows.isEmpty {
            sectionTitle(title)
            ForEach(rows) { BranchRowView(row: $0, model: model) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(LosttyTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(LosttyTheme.textSecondary)
            .multilineTextAlignment(.center)
    }

    private func centered<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        VStack { Spacer(); view(); Spacer() }
            .frame(maxWidth: .infinity)
            .padding(16)
    }
}

/// One branch: a compact line, and its details when expanded.
private struct BranchRowView: View {
    let row: BranchRow
    @ObservedObject var model: BranchesModel
    @State private var hovering = false

    private var expanded: Bool { model.expanded.contains(row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.toggle(row.id) } label: { line }
                .buttonStyle(.plain)
            if expanded { detail }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(expanded ? 0.06 : hovering ? 0.04 : 0)))
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
    }

    private var line: some View {
        HStack(spacing: 6) {
            Text(row.branch.name)
                .font(LosttyFont.mono(size: 12, weight: row.sessions.isEmpty ? .regular : .semibold))
                .foregroundStyle(LosttyTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isBase { tag("base", LosttyTheme.textSecondary) }
            if row.isRebasing { tag("rebasing", LosttyTheme.warning) }
            Spacer(minLength: 4)
            if !row.isBase, let text = BranchesFormat.aheadBehind(row.branch.vsBase ?? model.details[row.id]?.vsBase) {
                Text(text).font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary)
            }
            Text(BranchesFormat.relative.localizedString(for: row.branch.lastCommit, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(LosttyTheme.textSecondary)
                .lineLimit(1)
            HStack(spacing: -4) {
                ForEach(row.sessions.prefix(4)) { SessionAvatar(session: $0) }
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.branch.subject)
                .font(.system(size: 12))
                .foregroundStyle(LosttyTheme.textPrimary)
                .lineLimit(2)
            let details = model.details[row.id]
            VStack(alignment: .leading, spacing: 2) {
                if let path = row.worktreePath { fact("Worktree \((path as NSString).abbreviatingWithTildeInPath)") }
                fact(BranchesFormat.upstream(row.branch.upstream))
                if let files = details?.changedFiles, !row.isBase {
                    fact("\(BranchesFormat.count(files, "file")) changed vs \(model.snapshot?.base ?? "base")")
                }
                if let dirty = details?.dirtyCount, dirty > 0 {
                    fact("\(BranchesFormat.count(dirty, "uncommitted change"))")
                }
            }
            if !row.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(row.sessions) { SessionLine(session: $0) }
                }
            }
            if !row.isBase { SummaryBlock(row: row, model: model) }
        }
        .padding(.leading, 2)
    }

    private func fact(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary).lineLimit(1)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 0.5))
    }
}

/// The summary for one branch, and the button that asks for it.
private struct SummaryBlock: View {
    let row: BranchRow
    @ObservedObject var model: BranchesModel

    var body: some View {
        let cached = model.summary(for: row.id)
        let outdated = cached?.isOutdated(tip: row.branch.tip) ?? false
        VStack(alignment: .leading, spacing: 6) {
            if let cached {
                Text(cached.text)
                    .font(.system(size: 12))
                    .foregroundStyle(LosttyTheme.textPrimary.opacity(outdated ? 0.55 : 0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if outdated {
                    Text("Outdated: the branch has moved since.")
                        .font(.system(size: 10))
                        .foregroundStyle(LosttyTheme.warning)
                }
            }
            switch model.summaryState(for: row.id) {
            case .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…").font(.system(size: 11)).foregroundStyle(LosttyTheme.textSecondary)
                    Button("Cancel") { model.cancelSummary(row.id) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(LosttyTheme.danger)
                summarizeButton(cached == nil ? "Retry" : "Re-summarize")
            case nil:
                summarizeButton(cached == nil ? "Summarize" : outdated ? "Re-summarize" : "Summarize again")
            }
        }
    }

    private func summarizeButton(_ title: String) -> some View {
        Button(title) { model.summarize(row.id) }
            .controlSize(.small)
            .disabled(!model.canSummarize)
            .help(model.claude == .missing ? "Install Claude Code to summarize" : "Ask Claude what this branch does")
    }
}

/// A session in an expanded row: click to go to it.
private struct SessionLine: View {
    let session: BranchSession

    var body: some View {
        Button { BranchesActions.open(session) } label: {
            HStack(spacing: 6) {
                SessionAvatar(session: session)
                Text(session.title)
                    .font(.system(size: 12))
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if session.isPhone {
                    Text("phone").font(.system(size: 10)).foregroundStyle(LosttyTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.isPhone ? "Open in a new tab" : "Go to this pane")
    }
}

/// The agent's state dot. It pulses while working and is steady otherwise,
/// whenever the state changes while the dot stays on screen.
private struct AgentDot: View {
    let agent: AgentState
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
            .opacity(agent == .working && pulse ? 0.35 : 1)
            .onAppear { restart() }
            .onChange(of: agent) { _ in restart() }
    }

    private func restart() {
        var stop = Transaction()
        stop.disablesAnimations = true
        withTransaction(stop) { pulse = false }
        guard agent == .working else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
        }
    }
}

/// A session's initial (or a phone), with its agent's state as a dot.
private struct SessionAvatar: View {
    let session: BranchSession
    var body: some View {
        ZStack {
            Circle().fill(LosttyTheme.surfaceRaised)
            Circle().strokeBorder(LosttyTheme.hairline, lineWidth: 1)
            if session.isPhone {
                Image(systemName: "iphone").font(.system(size: 8, weight: .semibold))
            } else {
                Text(BranchesFormat.initial(session.title)).font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(LosttyTheme.textPrimary)
        .frame(width: 18, height: 18)
        .overlay(alignment: .bottomTrailing) {
            if let agent = session.agent {
                AgentDot(agent: agent, color: color(agent))
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel(label)
    }

    private func color(_ agent: AgentState) -> Color {
        switch agent {
        case .working: LosttyTheme.accent
        case .idle: LosttyTheme.success
        case .waiting: LosttyTheme.warning
        }
    }

    private var label: String {
        switch session.agent {
        case .working: "\(session.title), agent working"
        case .idle: "\(session.title), Claude idle"
        case .waiting: "\(session.title), agent waiting for you"
        case nil: session.title
        }
    }
}

/// "‹ Apps" on the left, the repo on the right.
struct BranchesHeader: View {
    let title: String
    let subtitle: String?
    let busy: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Apps").font(.system(size: 12))
                }
                .foregroundStyle(LosttyTheme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to apps")
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Esc closes the panel, but only once the panel has focus (a click inside
/// it): Esc typed in the terminal stays with the terminal.
struct PanelEscape: ViewModifier {
    let onClose: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onTapGesture { focused = true }
            .onExitCommand(perform: onClose)
    }
}
#endif
