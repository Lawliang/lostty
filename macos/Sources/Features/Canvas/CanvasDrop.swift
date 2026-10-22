#if os(macOS)
import AppKit
import SwiftUI

/// A terminal window dragged by its title bar onto the canvas's title bar
/// moves onto the canvas. While the pointer is over the canvas's title bar
/// a band of lit glass shows there and the dragged window goes see-through;
/// letting go warps the window in (CanvasAbsorb) and makes it a card, tabs
/// and all. The window server moves the window, so the drag is followed by
/// watching the pointer and the mouse button until it's let go.
@MainActor
final class CanvasDrop: NSObject {
    static let shared = CanvasDrop()

    /// How see-through the dragged window is over the drop.
    static let hoverAlpha: CGFloat = 0.82

    private var watching = false
    private weak var dragging: TerminalController?
    private var timer: Timer?
    private var well: NSPanel?
    private var over = false

    /// Starts noticing terminal windows being dragged. Once, with the canvas.
    func start() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillMove(_:)), name: NSWindow.willMoveNotification, object: nil)
    }

    @objc private func windowWillMove(_ notification: Notification) {
        guard let controller = (notification.object as? NSWindow)?.windowController as? TerminalController else { return }
        dragStarted(controller)
    }

    /// The canvas's title bar, from its window's frame and the height of
    /// what's under the title bar, in screen coordinates.
    nonisolated static func titleBar(frame: CGRect, contentHeight: CGFloat) -> CGRect {
        let height = max(28, frame.height - contentHeight)
        return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    private func dragStarted(_ controller: TerminalController) {
        // Only a drag (the button down), with the canvas showing.
        guard timer == nil, NSEvent.pressedMouseButtons & 1 != 0, LosttyChannel.current.hasCanvas,
              let canvas = CanvasController.shared?.window, canvas.isVisible, !canvas.isMiniaturized,
              controller.window?.styleMask.contains(.fullScreen) == false else { return }
        dragging = controller
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { CanvasDrop.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let controller = dragging, let window = controller.window,
              let canvasController = CanvasController.shared, let canvas = canvasController.window else {
            return stop()
        }
        let point = NSEvent.mouseLocation
        let titleBar = Self.titleBar(frame: canvas.frame, contentHeight: canvas.contentLayoutRect.height)
        // Over the title bar, and nothing but the dragged window (and the
        // band) in front of the canvas there.
        let under = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: window.windowNumber)
        let inside = titleBar.contains(point) && [canvas.windowNumber, well?.windowNumber].contains(under)
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            hover(inside, titleBar: titleBar, canvas: canvas, dragged: window)
            return
        }
        stop()
        guard inside else { return }
        let controllers = (window.tabbedWindows ?? [window]).compactMap { $0.windowController as? TerminalController }
        let ghostty = controller.ghostty
        CanvasAbsorb.run(window, into: point) {
            CanvasImport.move(ghostty, controllers, focus: controller) { cards in
                for card in cards {
                    if let view = canvasController.views[card.id] { CanvasAbsorb.emerge(view) }
                }
            }
        }
    }

    private func hover(_ inside: Bool, titleBar: CGRect, canvas: NSWindow, dragged: NSWindow) {
        guard inside != over else { return }
        over = inside
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            dragged.animator().alphaValue = inside ? Self.hoverAlpha : 1
        }
        if inside {
            showWell(over: titleBar, canvas: canvas)
        } else {
            hideWell()
        }
    }

    private func showWell(over titleBar: CGRect, canvas: NSWindow) {
        let band = titleBar.insetBy(dx: 6, dy: 3)
        let well = self.well ?? CanvasAbsorb.overlay(frame: band)
        well.setFrame(band, display: false)
        well.level = canvas.level
        well.contentView = NSHostingView(rootView: CanvasDropWell())
        if well.parent == nil { canvas.addChildWindow(well, ordered: .above) }
        well.orderFront(nil)
        self.well = well
    }

    private func hideWell() {
        guard let well else { return }
        well.parent?.removeChildWindow(well)
        well.orderOut(nil)
        self.well = nil
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if over, let window = dragging?.window { window.alphaValue = 1 }
        over = false
        dragging = nil
        hideWell()
    }
}

/// The band over the canvas's title bar while a window can be let go
/// there: the + button's lit glass, its light slowly turning, with what
/// letting go does.
private struct CanvasDropWell: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 6) {
            Image(systemName: "square.on.square.dashed")
            Text("Release to Add to Canvas")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(dark ? Color.white : Color.black)
        .shadow(color: .white.opacity(dark ? 0.45 : 0), radius: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(CanvasAddLitGlass(shape: Capsule(), dark: dark, lit: shown, interactive: false,
                                    reduceMotion: reduceMotion))
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(CanvasAddButton.light) { shown = true } }
        .accessibilityElement(children: .combine)
    }
}
#endif
