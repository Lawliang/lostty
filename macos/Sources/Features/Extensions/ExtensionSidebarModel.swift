#if os(macOS)
import AppKit
import Combine

/// An extension reachable from the window's icon row, above the usage bar.
/// Order is the row's order.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case branches
    case skins

    /// How an open extension shows: over the terminal, or over the whole
    /// window below the title bar (the icon row and usage bar included),
    /// until closed from its own close button.
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

    /// The icon row is tucked away behind its handle until dragged up (or
    /// the handle clicked); each window starts with it tucked away.
    @Published var iconRowShown = false

    /// Gives keyboard focus back to the window's focused pane. Set by the
    /// window's controller.
    var focusTerminal: @MainActor () -> Void = {}

    /// The Branches panel's state; idle until Branches opens.
    let branches: BranchesModel

    /// The extensions this build offers, in sidebar order.
    let available: [LosttyExtension]
    /// The axolotl in the terminal's corner (beta only, and not on canvas
    /// cards).
    let showsMascot: Bool

    init(branches: BranchesModel? = nil, channel: LosttyChannel = .current, mascot: Bool = true) {
        self.branches = branches ?? BranchesModel()
        available = LosttyExtension.available(in: channel)
        showsMascot = mascot && channel.showsMascot
    }

    /// Clicking an icon opens its extension; clicking the open one closes it.
    /// One this build doesn't offer stays shut.
    func select(_ ext: LosttyExtension) {
        guard available.contains(ext) else { return }
        active = active == ext ? nil : ext
    }

    /// A panel's back button and Esc.
    func close() {
        active = nil
    }
}

/// The icon row's drawer: how much of the row shows while its handle is
/// dragged (`dragged` is the drag's height, negative upward), and whether
/// it ends shown when let go.
enum IconRowDrawer {
    static func reveal(shown: Bool, dragged: CGFloat) -> CGFloat {
        let height = ExtensionSidebarView.height
        return min(max((shown ? height : 0) - dragged, 0), height)
    }

    /// Past halfway, or flicked that way (`predicted`, where the drag
    /// would come to rest), it goes; otherwise it springs back.
    static func settle(shown: Bool, dragged: CGFloat, predicted: CGFloat) -> Bool {
        let half = ExtensionSidebarView.height / 2
        let travel = shown ? max(dragged, predicted) : -min(dragged, predicted)
        return travel > half ? !shown : shown
    }
}
#endif
