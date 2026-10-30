#if os(macOS)
import AppKit
import SwiftUI

/// Under the bottom bar while the focused pane's Claude has subagents or
/// background shells: a carousel of live thumbnails, newest first, each
/// its last few lines. Tapping one shows it in the terminal's place
/// (PaneTaskView). The window grows to make room for it.
struct PaneTaskStrip: View {
    static let height: CGFloat = 112
    static let thumbnailLines = 4

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var tasks = PaneTasks.shared
    @StateObject private var feed = TaskFeedModel()

    private var chrome: NSColor { model.chromeColor ?? .windowBackgroundColor }
    private var ink: Color { chrome.isLight ? .black : .white }
    private var list: [PaneTask] { model.focusedSurfaceID.flatMap { tasks.lists[$0] } ?? [] }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(list.reversed()) { task in
                    PaneTaskThumbnail(
                        task: task, entry: feed.entries[task.id], ink: ink,
                        open: model.openTaskID == task.id)
                        .onTapGesture { model.openTask(task.id) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .background(Color(nsColor: chrome))
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5) }
        .task(id: list) { await feed.watch(list, limit: Self.thumbnailLines) }
    }

    /// Grows `window` downward by `delta`, or shrinks it for a negative one,
    /// keeping its top. False when it can't grow: full screen, or no room
    /// left on the screen; the strip then takes its height from the
    /// terminal.
    static func resize(_ window: NSWindow, by delta: CGFloat) -> Bool {
        guard !window.styleMask.contains(.fullScreen) else { return false }
        var frame = window.frame
        frame.origin.y -= delta
        frame.size.height += delta
        if delta > 0, let visible = window.screen?.visibleFrame {
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            guard frame.maxY <= visible.maxY else { return false }
        }
        window.setFrame(frame, display: false)
        return true
    }
}

/// One subagent or shell in the strip: its name, then its last lines.
private struct PaneTaskThumbnail: View {
    let task: PaneTask
    let entry: TaskFeedEntry?
    let ink: Color
    let open: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: task.kind == .shell ? "terminal" : "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.85))
                Text(heading)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }
            .padding(.bottom, 2)
            ForEach(entry?.lines ?? []) { line in
                Text(line.text)
                    .font(ClaudeUsageFont.font(size: 10))
                    .foregroundStyle(PaneTaskView.color(line.style, ink: ink))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 210, height: PaneTaskStrip.height - 16, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ink.opacity(hovering ? 0.1 : 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ink.opacity(open ? 0.45 : 0.1), lineWidth: open ? 1 : 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .help("Show it in the terminal's place")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "Explore · Find where zones load", or the shell's description.
    private var heading: String {
        guard task.kind == .subagent, let caption = entry?.caption else { return task.title }
        return "\(task.title) · \(caption)"
    }
}

/// The open subagent or shell in the terminal's place, following it live,
/// with a way back to the terminal (its button, or Esc).
struct PaneTaskView: View {
    static let lines = 2000

    let task: PaneTask
    @ObservedObject var model: ExtensionSidebarModel
    @StateObject private var feed = TaskFeedModel()

    private var chrome: NSColor { model.chromeColor ?? .windowBackgroundColor }
    private var ink: Color { chrome.isLight ? .black : .white }
    private var entry: TaskFeedEntry? { feed.entries[task.id] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.closeTask() } label: {
                    Label("Terminal", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.9))
                .keyboardShortcut(.cancelAction)
                .help("Back to the terminal (Esc)")
                Text(heading)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entry?.lines ?? []) { line in
                            Text(line.text)
                                .font(ClaudeUsageFont.font(size: 12))
                                .foregroundStyle(Self.color(line.style, ink: ink))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id(Self.end)
                    }
                    .textSelection(.enabled)
                    .padding(12)
                }
                .onChange(of: entry?.lines.last) { _ in proxy.scrollTo(Self.end, anchor: .bottom) }
            }
        }
        .background(Color(nsColor: chrome))
        .task(id: task.id) { await feed.watch([task], limit: Self.lines) }
    }

    private static let end = "end"

    private var heading: String {
        guard task.kind == .subagent, let caption = entry?.caption else { return task.title }
        return "\(task.title) · \(caption)"
    }

    static func color(_ style: FeedLine.Style, ink: Color) -> Color {
        switch style {
        case .brief: ink.opacity(0.45)
        case .action: ink.opacity(0.7)
        case .failed: Color(red: 0.95, green: 0.4, blue: 0.4)
        case .words: ink.opacity(0.9)
        case .done: Color(red: 0.4, green: 0.8, blue: 0.5)
        }
    }
}

/// PaneTaskView over the terminal while one is open.
struct PaneTaskOverlay: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var tasks = PaneTasks.shared

    var body: some View {
        if let id = model.openTaskID, let pane = model.focusedSurfaceID,
           let task = tasks.lists[pane]?.first(where: { $0.id == id }) {
            PaneTaskView(task: task, model: model)
                .transition(.opacity)
        }
    }
}
#endif
