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
