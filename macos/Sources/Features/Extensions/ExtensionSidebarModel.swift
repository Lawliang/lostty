#if os(macOS)
import AppKit
import Combine

/// An extension reachable from the bottom bar's apps button. Order is the
/// order the bar shows them in.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case branches
    case skins

    /// How an open extension shows: over the terminal, or over the whole
    /// window below the title bar (the bottom bar included), until closed
    /// from its own close button.
    enum Presentation: Equatable {
        case overlay
        case window
    }

    var id: String { rawValue }

    /// The extensions `channel` offers, in sidebar order: Branches is beta
    /// only.
    static func available(in channel: LosttyChannel) -> [LosttyExtension] {
        allCases.filter { $0 != .branches || channel.hasBranches }
    }

    var title: String {
        switch self {
        case .branches: "Branches"
        case .skins: "Skins"
        }
    }

    var presentation: Presentation {
        switch self {
        case .branches: .window
        case .skins: .overlay
        }
    }
}

/// Per-window sidebar state: which extension (if any) is open in the
/// terminal area, the pane extensions act on, and the window's title bar
/// color, which the sidebar matches.
@MainActor
final class ExtensionSidebarModel: ObservableObject {
    @Published private(set) var active: LosttyExtension? {
        didSet {
            guard active != oldValue else { return }
            if active == .branches {
                branches.open(focused: focusedSurfaceID)
            } else if oldValue == .branches {
                branches.close()
            }
            // A closing app may hold keyboard focus (the Branches panel takes
            // it, for Esc); hand it back to the pane. Branches giving way to
            // another app does the same, since that app doesn't take focus.
            if oldValue != nil, active == nil || oldValue == .branches {
                focusTerminal()
            }
        }
    }
    /// The window's focused (or last focused) pane, set by the controller.
    @Published var focusedSurfaceID: UUID? {
        didSet {
            if active == .branches, focusedSurfaceID != oldValue { branches.focusChanged(focusedSurfaceID) }
        }
    }
    /// The title bar's color (the top pane's background), set by the window.
    @Published var chromeColor: NSColor?
    /// The bottom bar shows the apps in place of Claude's usage.
    @Published private(set) var showsApps = false
    /// A new window's "what's it for?" question, over everything in it.
    @Published var newWindowPrompt: NewWindowPrompt?

    /// Gives keyboard focus back to the window's focused pane. Set by the
    /// window's controller.
    var focusTerminal: @MainActor () -> Void = {}

    /// The strip of the focused pane's subagents and shells shows under the
    /// bottom bar (PaneTaskStrip).
    @Published private(set) var showsTasks = false
    /// The one shown in the terminal's place (PaneTaskView), by id.
    @Published private(set) var openTaskID: String?
    /// Grows the window (or card) by `delta`, or shrinks it for a negative
    /// one, so the terminal keeps its size as the strip comes and goes;
    /// false when it can't. Set by the window's controller.
    var resizeForTasks: @MainActor (CGFloat) -> Bool = { _ in false }
    private var grewForTasks = false
    private var tasksWatch: AnyCancellable?

    /// The Branches panel's state; idle until Branches opens.
    let branches: BranchesModel

    /// The extensions this build offers, in sidebar order.
    let available: [LosttyExtension]
    /// The notification bubbles at the terminal's top right (not on canvas
    /// cards: the canvas shows one stack for all of them).
    let showsNotifications: Bool

    init(
        branches: BranchesModel? = nil, channel: LosttyChannel = .current, notifications: Bool = true
    ) {
        self.branches = branches ?? BranchesModel()
        available = LosttyExtension.available(in: channel)
        showsNotifications = notifications
        tasksWatch = PaneTasks.shared.$lists.combineLatest($focusedSurfaceID)
            .sink { [weak self] lists, pane in
                MainActor.assumeIsolated { self?.tasksChanged(pane.flatMap { lists[$0] } ?? []) }
            }
    }

    /// Shows a subagent or shell in the terminal's place. The pane gives up
    /// keyboard focus meanwhile, so Esc comes back rather than reaching it.
    func openTask(_ id: String) {
        openTaskID = id
        if let pane = focusedSurfaceID, let window = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane)?.window {
            window.makeFirstResponder(nil)
        }
    }

    func closeTask() {
        guard openTaskID != nil else { return }
        openTaskID = nil
        focusTerminal()
    }

    /// The focused pane's tasks changed: the strip comes or goes, growing
    /// or shrinking the window first so the terminal is laid out once.
    private func tasksChanged(_ list: [PaneTask]) {
        if let open = openTaskID, !list.contains(where: { $0.id == open }) { closeTask() }
        let shown = !list.isEmpty
        guard shown != showsTasks else { return }
        if shown {
            grewForTasks = resizeForTasks(PaneTaskStrip.height)
        } else if grewForTasks {
            _ = resizeForTasks(-PaneTaskStrip.height)
            grewForTasks = false
        }
        showsTasks = shown
    }

    /// Clicking an icon opens its extension; clicking the open one closes it.
    /// One this build doesn't offer stays shut.
    func select(_ ext: LosttyExtension) {
        guard available.contains(ext) else { return }
        active = active == ext ? nil : ext
    }

    /// The bottom bar's apps button: shows the apps, or puts the usage back.
    /// An open app stays open either way.
    func toggleApps() {
        showsApps.toggle()
    }

    /// A panel's back button and Esc.
    func close() {
        active = nil
    }
}
#endif
