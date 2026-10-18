#if os(macOS)
import AppKit
import Foundation

/// Every terminal window as Restart to Update found it: where each window
/// was, which windows were tabs of one another and in what order, which tab
/// was showing, and each tab's splits (each pane keeps its UUID, so its
/// launcher reattaches to its session). Carried in the `RestartHandoff`;
/// the next Lostty rebuilds the windows from it instead of leaving them to
/// macOS's window restoration (`LosttyRestart.restoresFromSnapshot`).
struct WindowSnapshot: Codable, Equatable {
    /// One window and its tabs.
    struct Group: Codable, Equatable {
        /// `NSWindow.frame`, in screen coordinates.
        var frame: CGRect
        /// Which of `tabs` was showing.
        var selected: Int
        var miniaturized: Bool
        /// Each tab's `TerminalRestorableState`, as JSON, in tab order.
        var tabs: [Data]
    }

    /// Front to back; minimized windows last.
    var groups: [Group]

    /// Windows as their tab groups, in tab order, front to back: a group
    /// ranks by its frontmost window in `frontToBack`; groups with none
    /// there (minimized) follow, in the order they were found.
    static func arrange<W: Hashable>(_ windows: [W], tabs: (W) -> [W], frontToBack: [W]) -> [[W]] {
        var groups: [[W]] = []
        var seen: Set<W> = []
        for window in windows where !seen.contains(window) {
            let group = tabs(window).isEmpty ? [window] : tabs(window)
            seen.formUnion(group)
            groups.append(group)
        }
        let rank = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        let ranked = groups.enumerated().map { index, group in
            (group, group.compactMap { rank[$0] }.min() ?? Int.max, index)
        }
        return ranked.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }

    /// `frame` if enough of it is on one of `screens` (visible frames) to
    /// grab, else nil: a display that's gone leaves the window where macOS
    /// puts a new one.
    static func placement(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        let minimum: CGFloat = 40
        let fits = screens.contains { screen in
            let overlap = screen.intersection(frame)
            return !overlap.isNull && overlap.width >= minimum && overlap.height >= minimum
        }
        return fits ? frame : nil
    }
}

@MainActor
extension WindowSnapshot {
    /// The terminal windows open now; nil when there are none.
    static func capture() -> WindowSnapshot? {
        let controllers = TerminalController.all
        let windows = controllers.compactMap(\.window)
        let arranged = arrange(windows, tabs: { $0.tabbedWindows ?? [] }, frontToBack: NSApp.orderedWindows)
        let encoder = JSONEncoder()
        let groups: [Group] = arranged.compactMap { windows in
            let tabs = windows.compactMap { window -> Data? in
                guard let controller = window.windowController as? TerminalController,
                      !controller.surfaceTree.isEmpty else { return nil }
                return try? encoder.encode(TerminalRestorableState(from: controller))
            }
            guard !tabs.isEmpty, let first = windows.first else { return nil }
            let showing = first.tabGroup?.selectedWindow ?? first
            return Group(
                frame: first.frame,
                selected: windows.firstIndex(of: showing) ?? 0,
                miniaturized: windows.contains(where: \.isMiniaturized),
                tabs: tabs)
        }
        return groups.isEmpty ? nil : WindowSnapshot(groups: groups)
    }

    /// Opens every window as it was, back to front, so the front one ends up
    /// in front and key. Returns how many windows (tabs) it opened.
    @discardableResult
    func restore(_ ghostty: Ghostty.App) -> Int {
        let decoder = JSONDecoder()
        let screens = NSScreen.screens.map(\.visibleFrame)
        var front: NSWindow?
        var opened = 0
        for group in groups.reversed() {
            let tabs = group.tabs.compactMap { data -> (TerminalController, TerminalRestorableState)? in
                guard let state = try? decoder.decode(TerminalRestorableState.self, from: data),
                      let controller = TerminalWindowRestoration.controller(ghostty, state: state) else { return nil }
                return (controller, state)
            }
            guard let first = tabs.first?.0, let firstWindow = first.window else { continue }
            first.showWindow(nil)
            if let frame = Self.placement(group.frame, screens: screens) {
                firstWindow.setFrame(frame, display: true)
            }
            var previous = firstWindow
            for (controller, _) in tabs.dropFirst() {
                guard let window = controller.window else { continue }
                controller.showWindow(nil)
                _ = previous.addTabbedWindowSafely(window, ordered: .above)
                previous = window
            }
            opened += tabs.count

            let showing = tabs[min(max(group.selected, 0), tabs.count - 1)]
            showing.0.window?.makeKeyAndOrderFront(nil)
            if let mode = showing.1.effectiveFullscreenMode {
                showing.0.toggleFullscreen(mode: mode)
            }
            if group.miniaturized {
                showing.0.window?.miniaturize(nil)
            } else {
                front = showing.0.window
            }
        }
        front?.makeKeyAndOrderFront(nil)
        return opened
    }
}

/// "Saving your windows…": shown while a restart gets ready to quit, so
/// the pause before the windows close has a reason.
@MainActor
final class SavingWindowsPanel {
    private let panel: NSPanel

    init() {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        // Keeps turning while the main thread does the saving.
        spinner.usesThreadedAnimation = true
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Saving your windows…")
        label.font = .systemFont(ofSize: 13, weight: .medium)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 20)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentView = background
        panel.setContentSize(stack.fittingSize)
    }

    /// Centered over `window` (else the main screen), drawn right away.
    func show(over window: NSWindow?) {
        let area = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func close() {
        panel.orderOut(nil)
    }
}
#endif
