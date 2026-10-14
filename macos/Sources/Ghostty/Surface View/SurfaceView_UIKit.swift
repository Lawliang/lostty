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
        @Published var title: String = "Lostty"

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
            didSet {
                if ctrlLatched != oldValue, ctrlLatched { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                keyboard.ctrlLatched = ctrlLatched
            }
        }
        private lazy var keyRow: KeyRowView = {
            let row = KeyRowView()
            row.onKey = { [weak self] key in self?.rowKey(key) }
            return row
        }()
        /// Lostty's keyboard (return makes a new line, Send sends), unless the
        /// key row's globe switched to iOS's for now; the globe switches back,
        /// and it's back anyway the next time the keyboard opens.
        private var usesLosttyKeyboard = true
        private lazy var keyboard: TerminalKeyboardView = {
            let keyboard = TerminalKeyboardView()
            keyboard.onText = { [weak self] text in self?.insertText(text) }
            keyboard.onBackspace = { [weak self] in self?.deleteBackward() }
            keyboard.onNewline = { [weak self] in self?.sendIgnoringCtrl(MobileInput.newline) }
            keyboard.onCtrl = { [weak self] in self?.ctrlLatched.toggle() }
            keyboard.onRowKey = { [weak self] key in self?.rowKey(key) }
            keyboard.onDismiss = { [weak self] in _ = self?.resignFirstResponder() }
            keyboard.onSwipe = { [weak self] swipe in
                guard let self else { return }
                let ctrl = self.ctrlLatched
                self.ctrlLatched = false
                self.send([swipe.press(ctrl: ctrl)])
            }
            keyboard.onSend = { [weak self] in self?.sendIgnoringCtrl(MobileInput.enter) }
            return keyboard
        }()
        /// A flick still scrolling after the finger lifted; holds the view
        /// until stopped.
        private var scrollMomentum: CADisplayLink?
        /// The flick's speed, in points per second.
        private var scrollVelocity: CGFloat = 0
        /// Finger travel not yet sent as a line, in points.
        private var pendingScroll: CGFloat = 0
        /// Where the last scroll was sent, inside the view.
        private var scrollPoint: CGPoint = .zero
        /// `ghostty_input_scroll_mods_t` with only the precision bit set.
        private static let preciseScroll: ghostty_input_scroll_mods_t = 1
        /// Slower than this, in points per second, a flick stops.
        private static let momentumMinimum: CGFloat = 40
        /// The link the core reports under the pointer (its mouse-over-link
        /// action); only meaningful during `link(at:)`.
        var hoveredLink: String?
        /// Lostty Mobile: the pane's history, scrolled on the phone; without
        /// one, scrolling sends tmux the wheel.
        var scrollback: ScrollbackSource? {
            didSet {
                scroller?.leave()
                scroller = scrollback.map { ScrollbackScroller(host: self, source: $0) }
            }
        }
        private var scroller: ScrollbackScroller?

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
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
            // The history's copy reaches a line above the top.
            clipsToBounds = true
            if KeyboardDebugLog.enabled { watchKeyboardForDebugLog() }
        }

        /// Every show and hide of the keyboard, for the debug log.
        private func watchKeyboardForDebugLog() {
            let center = NotificationCenter.default
            let names: [(Foundation.Notification.Name, String)] = [
                (UIResponder.keyboardWillShowNotification, "keyboard will SHOW"),
                (UIResponder.keyboardWillHideNotification, "keyboard will HIDE"),
                (UIResponder.keyboardDidHideNotification, "keyboard did hide"),
                (UIApplication.willResignActiveNotification, "app will resign active"),
                (UIApplication.didBecomeActiveNotification, "app did become active"),
            ]
            for (name, what) in names {
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect).map {
                        String(format: " frame y=%.0f h=%.0f", $0.minY, $0.height)
                    } ?? ""
                    MainActor.assumeIsolated {
                        KeyboardDebugLog.log("\(what)\(frame) [terminal first responder: \(self?.isFirstResponder ?? false)]")
                    }
                }
            }
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
        /// Over iOS's keyboard only: esc and the way back. Lostty's has its
        /// own keys, and its grabber.
        override var inputAccessoryView: UIView? { usesLosttyKeyboard ? nil : keyRow }
        override var inputView: UIView? { usesLosttyKeyboard ? keyboard : nil }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            KeyboardDebugLog.log("terminal becomeFirstResponder -> \(became) (\(usesLosttyKeyboard ? "Lostty" : "iOS") keyboard)")
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            KeyboardDebugLog.log("terminal RESIGN first responder -> \(resigned); asked by: \(KeyboardDebugLog.caller())")
            // Next time, Lostty's keyboard again.
            if resigned { usesLosttyKeyboard = true }
            return resigned
        }

        func showKeyboard() {
            _ = becomeFirstResponder()
        }

        /// Shows the keyboard once a push or pop under way has finished:
        /// raised mid-push, it rides in with the screen from the side
        /// rather than up from the bottom.
        func showKeyboardWhenSettled() {
            // On appearing, the view may not be in its controller yet.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let coordinator = self.owningViewController?.transitionCoordinator else {
                    self.showKeyboard()
                    return
                }
                coordinator.animate(alongsideTransition: nil) { [weak self] context in
                    if !context.isCancelled { self?.showKeyboard() }
                }
            }
        }

        private var owningViewController: UIViewController? {
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }

        /// A tap on a link opens it; anywhere else brings up the keyboard,
        /// back at the newest line.
        @objc private func tapped(_ tap: UITapGestureRecognizer) {
            let point = tap.location(in: self)
            if let url = scroller?.isShowing == true ? scroller?.link(at: point) : link(at: point) {
                UIApplication.shared.open(url)
                return
            }
            scroller?.leave()
            KeyboardDebugLog.log("terminal tapped -> show keyboard")
            showKeyboard()
        }

        /// The link at `point`: a URL in the text or an OSC 8 hyperlink.
        /// The core finds links under a pointer held with ⌘, as on the Mac,
        /// and with ⇧ too while the program (tmux) takes the mouse; it
        /// reports one as hovered, during the call. The pointer then goes
        /// back off screen, so nothing stays highlighted.
        func link(at point: CGPoint) -> URL? {
            guard let surface else { return nil }
            hoveredLink = nil
            let mods = ghostty_input_mods_e(rawValue: GHOSTTY_MODS_SUPER.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
            ghostty_surface_mouse_pos(surface, point.x, point.y, mods)
            let found = hoveredLink
            ghostty_surface_mouse_pos(surface, -1, -1, GHOSTTY_MODS_NONE)
            hoveredLink = nil
            // Only real URLs: a file path means the Mac's files, not the phone's.
            guard let found, let url = URL(string: found), let scheme = url.scheme,
                  scheme.lowercased() != "file" else { return nil }
            return url
        }

        /// A vertical pan scrolls (the history on the phone, or tmux's with
        /// the wheel), and a flick keeps going, slowing down as a scroll view
        /// does.
        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed, .ended:
                if pan.state == .began {
                    stopScrollMomentum()
                    pendingScroll = 0
                    scroller?.began()
                }
                scroll(by: pan.translation(in: self).y, at: pan.location(in: self))
                pan.setTranslation(.zero, in: self)
                if pan.state == .ended { startScrollMomentum(velocity: pan.velocity(in: self).y) }
            default:
                break
            }
        }

        /// A touch stops a flick, as it does in a scroll view.
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            stopScrollMomentum()
            super.touchesBegan(touches, with: event)
        }

        private func scroll(by points: CGFloat, at location: CGPoint) {
            guard points != 0 else { return }
            // iOS has no mouse, so the core's cursor sits at (-1,-1) and
            // drops wheel events outside the viewport: put it under the finger.
            // A finger dragged past the edge keeps scrolling: clamp to bounds.
            scrollPoint = CGPoint(
                x: min(max(location.x, bounds.minX), bounds.maxX),
                y: min(max(location.y, bounds.minY), bounds.maxY))
            if scroller?.scroll(by: points) == true { return }
            wheel(by: points)
        }

        /// Scrolls with the wheel at the last scroll's point.
        func wheel(by points: CGFloat) {
            guard let surface else { return }
            // tmux scrolls whole lines (Lostty's tmux.conf: a line per wheel
            // event), so send a line once the finger is past half of one:
            // the text stays within half a line of the finger instead of
            // trailing it by up to a whole one.
            let cell = CGFloat(surfaceSize?.cell_height_px ?? 0)
            guard cell > 0 else { return }
            let line = cell / contentScaleFactor
            pendingScroll += points
            let rows = (pendingScroll / line).rounded()
            guard rows != 0 else { return }
            pendingScroll -= rows * line
            ghostty_surface_mouse_pos(surface, scrollPoint.x, scrollPoint.y, GHOSTTY_MODS_NONE)
            // A precise scroll is in pixels; whole rows of them are exactly
            // that many wheel events.
            ghostty_surface_mouse_scroll(surface, 0, Double(rows * cell), Self.preciseScroll)
        }

        private func startScrollMomentum(velocity: CGFloat) {
            guard abs(velocity) > Self.momentumMinimum else { return }
            scrollVelocity = velocity
            let link = CADisplayLink(target: self, selector: #selector(scrollMomentumStep(_:)))
            link.add(to: .main, forMode: .common)
            scrollMomentum = link
        }

        @objc private func scrollMomentumStep(_ link: CADisplayLink) {
            let seconds = link.targetTimestamp - link.timestamp
            scroll(by: scrollVelocity * seconds, at: scrollPoint)
            // A scroll view's normal deceleration is per millisecond.
            scrollVelocity *= pow(UIScrollView.DecelerationRate.normal.rawValue, seconds * 1000)
            if abs(scrollVelocity) < Self.momentumMinimum { stopScrollMomentum() }
        }

        private func stopScrollMomentum() {
            scrollMomentum?.invalidate()
            scrollMomentum = nil
        }

        func send(_ presses: [MobileInput.Press]) {
            guard let surface else { return }
            // Typing goes where the newest line is.
            scroller?.leave()
            for press in presses {
                press.withCValue(action: GHOSTTY_ACTION_PRESS) { _ = ghostty_surface_key(surface, $0) }
                press.withCValue(action: GHOSTTY_ACTION_RELEASE) { _ = ghostty_surface_key(surface, $0) }
            }
        }

        /// New line and Send are what they are, Ctrl or not.
        private func sendIgnoringCtrl(_ press: MobileInput.Press) {
            ctrlLatched = false
            send([press])
        }

        private func rowKey(_ key: MobileInput.RowKey) {
            if key == .keyboard {
                // Lostty's keyboard ⇄ iOS's (emoji, dictation, languages).
                usesLosttyKeyboard.toggle()
                KeyboardDebugLog.log("switch keyboards -> \(usesLosttyKeyboard ? "Lostty" : "iOS")")
                reloadInputViews()
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
            // Not the layers of subviews (the history's copy).
            let viewLayers = Set(subviews.map { ObjectIdentifier($0.layer) })
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for sublayer in layer.sublayers ?? [] where !viewLayers.contains(ObjectIdentifier(sublayer)) {
                sublayer.frame = bounds
                sublayer.contentsScale = contentScaleFactor
            }
            CATransaction.commit()
            scroller?.layout()
        }

        override func didMoveToWindow() {
            // A view backed by a Metal layer starts at 1x: the terminal drew
            // at one pixel per point and the screen stretched it, blurring
            // the text. Draw at the screen's own scale.
            if let window {
                contentScaleFactor = window.screen.scale
            } else {
                // Off screen (kept warm for a quick return): a flick can't keep
                // scrolling, nor its display link keep the view alive.
                stopScrollMomentum()
                scroller?.leave()
            }
            // A warm terminal still reads its output, so it reopens current,
            // but drawing frames nobody sees only heats the phone. Coming
            // back on screen draws it at once.
            if let surface {
                ghostty_surface_set_occlusion(surface, window != nil)
            }
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
        Ghostty.KeyboardDebugLog.log("    typed \(text.debugDescription)\(ctrlLatched ? " with ctrl" : "")")
        let ctrl = ctrlLatched
        ctrlLatched = false
        send(Ghostty.MobileInput.presses(typed: text, ctrl: ctrl))
    }

    func deleteBackward() {
        Ghostty.KeyboardDebugLog.log("    typed backspace")
        ctrlLatched = false
        send([Ghostty.MobileInput.backspace])
    }
}
