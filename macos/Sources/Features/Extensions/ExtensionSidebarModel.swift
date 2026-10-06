#if os(macOS)
import AppKit
import Combine

/// An extension reachable from the window's sidebar. Order is sidebar order.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case codebaseVisualizer
    case skins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codebaseVisualizer: "Codebase visualizer"
        case .skins: "Skins"
        }
    }
}

/// Per-window sidebar state: which extension (if any) is open in the
/// terminal area, the pane extensions act on, and the window's title bar
/// color, which the sidebar matches.
@MainActor
final class ExtensionSidebarModel: ObservableObject {
    @Published private(set) var active: LosttyExtension?
    /// The window's focused (or last focused) pane, set by the controller.
    @Published var focusedSurfaceID: UUID?
    /// The title bar's color (the top pane's background), set by the window.
    @Published var chromeColor: NSColor?

    /// Clicking an icon opens its extension; clicking the open one closes it.
    func select(_ ext: LosttyExtension) {
        active = active == ext ? nil : ext
    }
}
#endif
