#if os(macOS)
import Foundation

/// When a hidden sidebar shows: opened from its handle on the window's
/// right edge (a click, or a drag to the left past half its width) until
/// closed the same way, and while an app is open.
struct SidebarAutoHide: Equatable {
    /// Opened from the handle.
    private(set) var open = false
    private var appOpen = false

    var isVisible: Bool { open || appOpen }

    /// A click on the handle.
    mutating func toggle() {
        open = !isVisible
    }

    mutating func appChanged(open appOpen: Bool) {
        self.appOpen = appOpen
    }

    /// A drag of the handle let go heading for `predicted` points (where
    /// its speed would carry it; negative is leftward): the sidebar opens,
    /// or stays open, when it would end up more than half out.
    mutating func dragEnded(predicted: CGFloat, width: CGFloat) {
        open = Self.offset(open: isVisible, drag: predicted, width: width) < width / 2
    }

    /// How far right of its place the sidebar sits: `width` when hidden, 0
    /// when shown, following the handle in between while it is dragged.
    static func offset(open: Bool, drag: CGFloat?, width: CGFloat) -> CGFloat {
        min(width, max(0, (open ? 0 : width) + (drag ?? 0)))
    }
}

/// A window's `SidebarAutoHide`, and the handle's drag in progress.
@MainActor
final class SidebarAutoHideDriver: ObservableObject {
    @Published private(set) var machine = SidebarAutoHide()
    /// Points the handle has been dragged, nil when it isn't.
    @Published private(set) var drag: CGFloat?

    /// Shown at all, if only partly while the handle is dragged.
    var isVisible: Bool { machine.isVisible || drag != nil }

    func offset(width: CGFloat) -> CGFloat {
        SidebarAutoHide.offset(open: machine.isVisible, drag: drag, width: width)
    }

    func toggle() {
        machine.toggle()
    }

    func appChanged(open: Bool) {
        machine.appChanged(open: open)
    }

    func dragChanged(_ translation: CGFloat) {
        drag = translation
    }

    func dragEnded(predicted: CGFloat, width: CGFloat) {
        machine.dragEnded(predicted: predicted, width: width)
        drag = nil
    }

    /// Hiding was just turned on or off.
    func reset(appOpen: Bool) {
        machine = SidebarAutoHide()
        drag = nil
        machine.appChanged(open: appOpen)
    }
}
#endif
