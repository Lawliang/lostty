import SwiftUI
import GhosttyKit

extension Ghostty {
    /// The UIView implementation for a terminal surface.
    class SurfaceView: UIView, ObservableObject {
        typealias ID = UUID

        /// Unique ID per surface
        let id: UUID

        // The current title of the surface as defined by the pty. This can be
        // changed with escape codes. This is public because the callbacks go
        // to the app level and it is set from there.
        @Published var title: String = "👻"

        // The current pwd of the surface.
        @Published var pwd: String?

        // The cell size of this surface. This is set by the core when the
        // surface is first created and any time the cell size changes (i.e.
        // when the font size changes). This is used to allow windows to be
        // resized in discrete steps of a single cell.
        @Published var cellSize: OSSize = .zero

        // The health state of the surface. This currently only reflects the
        // renderer health. In the future we may want to make this an enum.
        @Published var healthy: Bool = true

        // Any error while initializing the surface.
        @Published var error: Error?

        // The hovered URL
        @Published var hoverUrl: String?

        // The progress report (if any)
        @Published var progressReport: Action.ProgressReport?

        // The time this surface last became focused. This is a ContinuousClock.Instant
        // on supported platforms.
        @Published var focusInstant: ContinuousClock.Instant?

        /// True when the bell is active. This is set inactive on focus or event.
        @Published var bell: Bool = false

        // The current search state. When non-nil, the search overlay should be shown.
        @Published var searchState: SearchState?

        // The currently active key tables. Empty if no tables are active.
        @Published var keyTables: [String] = []

        /// True when the surface is in readonly mode.
        @Published private(set) var readonly: Bool = false

        /// True when the surface should show a highlight effect (e.g., when presented via goto_split).
        @Published private(set) var highlighted: Bool = false

        // Returns sizing information for the surface. This is the raw C
        // structure because I'm lazy.
        var surfaceSize: ghostty_surface_size_s? {
            guard let surface = self.surface else { return nil }
            return ghostty_surface_size(surface)
        }

        private(set) var surface: ghostty_surface_t?

        /// Lostty Mobile: the remote IO of a remote surface.
        private let remoteIO: RemoteIO?
        /// The sticky Ctrl from the key row, used by the next key.
        var ctrlLatched = false {
            didSet { keyRow.setCtrl(ctrlLatched) }
        }
        private lazy var keyRow: KeyRowView = {
            let row = KeyRowView()
            row.onKey = { [weak self] key in self?.rowKey(key) }
            return row
        }()
        /// Scroll distance not yet sent, in points.
        private var pendingScroll: CGFloat = 0

        init(_ app: ghostty_app_t, baseConfig: SurfaceConfiguration? = nil, uuid: UUID? = nil) {
            self.id = uuid ?? .init()
            self.remoteIO = baseConfig?.remoteIO

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

            // Setup our surface. This will also initialize all the terminal IO.
            let surface_cfg = baseConfig ?? SurfaceConfiguration()
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
                ghostty_surface_new(app, &surface_cfg_c)
            }
            guard let surface = surface else {
                // TODO
                return
            }
            self.surface = surface

            // Lostty Mobile: a remote surface starts its session now.
            remoteIO?.attach(to: surface)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
            // Lostty Mobile: stop feeding before the surface is freed. Freeing
            // joins the core's threads, so no callback reaches remoteIO after.
            remoteIO?.detach()
            guard let surface = self.surface else { return }
            ghostty_surface_free(surface)
        }

        func focusDidChange(_ focused: Bool) {
            guard let surface = self.surface else { return }
            ghostty_surface_set_focus(surface, focused)

            // On macOS 13+ we can store our continuous clock...
            if focused {
                focusInstant = ContinuousClock.now
            }
        }

        func sizeDidChange(_ size: CGSize) {
            guard let surface = self.surface else { return }

            // Ghostty wants to know the actual framebuffer size... It is very important
            // here that we use "size" and NOT the view frame. If we're in the middle of
            // an animation (i.e. a fullscreen animation), the frame will not yet be updated.
            // The size represents our final size we're going for.
            let scale = self.contentScaleFactor
            ghostty_surface_set_content_scale(surface, scale, scale)
            ghostty_surface_set_size(
                surface,
                UInt32(size.width * scale),
                UInt32(size.height * scale)
            )
        }

        // MARK: UIView

        override var canBecomeFirstResponder: Bool { true }
        override var inputAccessoryView: UIView? { keyRow }

        func showKeyboard() {
            _ = becomeFirstResponder()
        }

        @objc private func tapped() {
            showKeyboard()
        }

        /// A vertical pan scrolls (tmux turns the wheel into its scrollback).
        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            guard let surface else { return }
            if pan.state == .began { pendingScroll = 0 }
            pendingScroll += pan.translation(in: self).y
            pan.setTranslation(.zero, in: self)
            // One wheel tick is multiplied by mouse-scroll-multiplier (3) and
            // tmux scrolls 5 lines per wheel event, so one tick per 15 rows
            // of finger travel moves the content 1:1 with the finger.
            let line = max(CGFloat(surfaceSize?.cell_height_px ?? 0) / contentScaleFactor, 8)
            let step = 15 * line
            let ticks = (pendingScroll / step).rounded(.towardZero)
            guard ticks != 0 else { return }
            pendingScroll -= ticks * step
            // iOS has no mouse, so the core's cursor sits at (-1,-1) and
            // drops wheel events outside the viewport: put it under the finger.
            // A finger dragged past the edge keeps scrolling: clamp to bounds.
            let raw = pan.location(in: self)
            let x = min(max(raw.x, bounds.minX), bounds.maxX)
            let y = min(max(raw.y, bounds.minY), bounds.maxY)
            ghostty_surface_mouse_pos(surface, x, y, GHOSTTY_MODS_NONE)
            ghostty_surface_mouse_scroll(surface, 0, Double(ticks), 0)
        }

        func send(_ presses: [MobileInput.Press]) {
            guard let surface else { return }
            for press in presses {
                press.withCValue(action: GHOSTTY_ACTION_PRESS) { _ = ghostty_surface_key(surface, $0) }
                press.withCValue(action: GHOSTTY_ACTION_RELEASE) { _ = ghostty_surface_key(surface, $0) }
            }
        }

        private func rowKey(_ key: MobileInput.RowKey) {
            if key == .ctrl {
                ctrlLatched.toggle()
                return
            }
            let ctrl = ctrlLatched
            ctrlLatched = false
            if let press = MobileInput.press(for: key, ctrl: ctrl) { send([press]) }
        }

        override class var layerClass: AnyClass {
            return CAMetalLayer.self
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Lostty Mobile: on iOS the renderer's IOSurfaceLayer is added as a
            // sublayer (not the view's own layer) and nothing sizes it, so it
            // stays 0x0 and draws nothing. Fit it to the view.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for sublayer in layer.sublayers ?? [] {
                sublayer.frame = bounds
                sublayer.contentsScale = contentScaleFactor
            }
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            sizeDidChange(frame.size)
        }
    }
}

extension Ghostty.SurfaceView: UIKeyInput {
    // Always true, so the keyboard's delete key always reaches us.
    var hasText: Bool { true }

    // UITextInputTraits: a terminal wants exactly what was typed. Declared
    // here, with the conformance, so UIKit sees them.
    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
    var smartDashesType: UITextSmartDashesType { get { .no } set {} }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { get { .no } set {} }
    var keyboardType: UIKeyboardType { get { .default } set {} }
    var keyboardAppearance: UIKeyboardAppearance { get { .dark } set {} }

    func insertText(_ text: String) {
        let ctrl = ctrlLatched
        ctrlLatched = false
        send(Ghostty.MobileInput.presses(typed: text, ctrl: ctrl))
    }

    func deleteBackward() {
        ctrlLatched = false
        send([Ghostty.MobileInput.backspace])
    }
}
