#if os(iOS)
import UIKit

extension Ghostty {
    /// Lostty Mobile's keyboard, in place of iOS's: letters, numbers and
    /// symbols (`MobileInput.Board`), a return key that makes a new line,
    /// and under the keys, where iOS puts the globe and mic, esc, the globe,
    /// send and flow. Holding the space bar switches to the iOS keyboard (the key
    /// row's globe switches back); the key row's grabber hides it.
    final class TerminalKeyboardView: UIInputView, UIInputViewAudioFeedback, UIGestureRecognizerDelegate {
        typealias Board = MobileInput.Board

        static let keyHeight: CGFloat = 42
        static let rowGap: CGFloat = 10
        static let keyGap: CGFloat = 6
        /// From the screen's edges: the same as between keys.
        static let side: CGFloat = keyGap
        /// The strip at the very top that holds the grabber; the keys start
        /// under it.
        static let top: CGFloat = 18
        /// Dragged this far down (or flicked), the keyboard closes.
        static let dismissDistance: CGFloat = 24
        /// The strip under the keys (Send), a row like the others.
        static let stripHeight: CGFloat = keyHeight
        static let stripGap: CGFloat = rowGap
        /// Send's extra width over the return key.
        static let sendExtra: CGFloat = 12
        /// Under the last row, down to the screen's edge: twice the gap
        /// between rows.
        static let bottomPadding: CGFloat = 2 * rowGap
        /// Held this long, the space bar switches keyboards.
        static let spaceHold: TimeInterval = 0.5
        /// Two Shift taps this close together lock caps.
        static let doubleTap: TimeInterval = 0.35
        static let repeatDelay: TimeInterval = 0.4
        static let repeatInterval: TimeInterval = 0.08

        /// The keys' and strip's height, above the home indicator.
        static var contentHeight: CGFloat {
            // The letter rows, then the strip.
            top + 4 * keyHeight + 3 * rowGap + stripGap + stripHeight
        }

        var onText: ((String) -> Void)?
        /// The grabber was pulled down (or tapped): close the keyboard.
        var onDismiss: (() -> Void)?
        private let grabber = UIView()
        var onBackspace: (() -> Void)?
        var onNewline: (() -> Void)?
        var onCtrl: (() -> Void)?
        /// Ctrl is latched (by this key or the key row's): shown lit.
        var ctrlLatched = false {
            didSet { if ctrlLatched != oldValue { refreshKeys() } }
        }
        var onSend: (() -> Void)?
        /// Not wired to anything yet.
        var onFlowMode: (() -> Void)?
        /// esc, or the keyboard switch (the globe, or the space bar held).
        var onRowKey: ((MobileInput.RowKey) -> Void)?
        /// A swipe across the keys: an arrow.
        var onSwipe: ((Board.Swipe) -> Void)?
        private let swipeFeedback = KeyboardSwipeFeedback()

        private var board: Board.Layer = .letters {
            didSet { if board != oldValue { buildKeys() } }
        }
        private var shift = Board.Shift.off {
            didSet { if shift != oldValue { refreshKeys() } }
        }
        private var lastShiftTap: Date?
        private var rows: [[(button: UIButton, slot: Board.Slot)]] = []
        private let send = SendKeyButton(frame: .zero)
        private let flowMode = UIButton(type: .system)
        private let esc = UIButton(type: .system)
        private let globe = UIButton(type: .system)
        private var repeatTimer: Timer?
        private let tap = UIImpactFeedbackGenerator(style: .light)
        /// The keyboard's height, down to the screen's edge. iOS sizes an
        /// input view once, as it first shows, from this.
        private lazy var height = heightAnchor.constraint(equalToConstant: Self.fullHeight)

        static var fullHeight: CGFloat { contentHeight + bottomPadding }

        var enableInputClicksWhenVisible: Bool { true }

        init() {
            // iOS takes the keyboard's height from this frame. Its own
            // background, not iOS's keyboard backdrop: square top corners.
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.fullHeight), inputViewStyle: .default)
            allowsSelfSizing = true
            height.isActive = true
            backgroundColor = Self.background
            buildGrabber()
            buildStrip()
            addSubview(swipeFeedback)
            buildKeys()
            let swipe = KeyboardSwipeRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.delegate = self
            addGestureRecognizer(swipe)
        }

        /// The keyboard's backdrop: between the screen and the keys.
        static let background = UIColor(red: 0x10 / 255, green: 0x0F / 255, blue: 0x13 / 255, alpha: 1)

        // MARK: Swipes: arrows

        /// Swipes start on the keys, not the grabber (that drag closes the
        /// keyboard).
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gesture is KeyboardSwipeRecognizer else { return true }
            return touch.location(in: self).y >= Self.top
        }

        @objc private func swiped(_ swipe: KeyboardSwipeRecognizer) {
            switch swipe.state {
            case .began:
                swipeFeedback.begin(at: swipe.start, to: swipe.current)
            case .changed:
                swipeFeedback.move(to: swipe.current)
            case .ended:
                // The arrow goes the moment the finger lifts; the feedback
                // only follows.
                let made = Board.Swipe.of(dx: swipe.translation.x, dy: swipe.translation.y)
                if let made {
                    feedback()
                    onSwipe?(made)
                }
                swipeFeedback.finish(made)
            default:
                swipeFeedback.finish(nil)
            }
        }

        // MARK: The grabber

        /// At the very top: drag it down (or tap it) to close the keyboard;
        /// tapping the terminal brings it back.
        private func buildGrabber() {
            let handle = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: Self.top))
            handle.autoresizingMask = [.flexibleWidth]
            handle.accessibilityLabel = "Hide Keyboard"
            handle.accessibilityTraits = .button
            handle.isAccessibilityElement = true
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
            handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTapped)))
            addSubview(handle)
            grabber.backgroundColor = LosttyUIColor.textPrimary.withAlphaComponent(0.35)
            grabber.layer.cornerRadius = 2.5
            grabber.isUserInteractionEnabled = false
            handle.addSubview(grabber)
            self.handle = handle
        }

        private var handle: UIView?

        /// Follows the finger a little, then closes the keyboard once pulled
        /// far enough (or flicked down); springs back otherwise.
        @objc private func dragged(_ pan: UIPanGestureRecognizer) {
            let down = max(0, pan.translation(in: self).y)
            switch pan.state {
            case .began, .changed:
                grabber.transform = CGAffineTransform(translationX: 0, y: min(down, Self.dismissDistance) / 3)
                grabber.alpha = down >= Self.dismissDistance ? 1 : 0.7
            case .ended:
                springBack()
                if down >= Self.dismissDistance || pan.velocity(in: self).y > 400 { hideKeyboard() }
            default:
                springBack()
            }
        }

        @objc private func handleTapped() { hideKeyboard() }

        private func hideKeyboard() {
            tap.impactOccurred(intensity: 0.6)
            onDismiss?()
        }

        private func springBack() {
            UIView.animate(withDuration: 0.2) {
                self.grabber.transform = .identity
                self.grabber.alpha = 1
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }


        // MARK: Keys

        private func buildKeys() {
            rows.flatMap { $0 }.forEach { $0.button.removeFromSuperview() }
            rows = Board.rows(board).map { row in
                row.map { slot in
                    let button = UIButton(configuration: .filled())
                    button.configurationUpdateHandler = { [weak self] button in
                        self?.style(button, for: slot.key)
                    }
                    wire(button, slot.key)
                    addSubview(button)
                    return (button, slot)
                }
            }
            refreshKeys()
            // Swipe feedback stays over the keys.
            bringSubviewToFront(swipeFeedback)
            setNeedsLayout()
        }

        private func refreshKeys() {
            for (button, _) in rows.flatMap({ $0 }) { button.setNeedsUpdateConfiguration() }
        }

        private func wire(_ button: UIButton, _ key: Board.Key) {
            switch key {
            case .backspace:
                // At once, then again and again while held.
                button.addAction(UIAction { [weak self] _ in self?.startRepeating { self?.onBackspace?() } }, for: .touchDown)
                for end: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
                    button.addAction(UIAction { [weak self] _ in self?.stopRepeating() }, for: end)
                }
            case .space:
                // A tap is a space; held, it switches keyboards (and the
                // press is cancelled, so no space follows).
                button.addAction(UIAction { [weak self] _ in self?.pressed(key) }, for: .touchUpInside)
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(spaceHeld(_:)))
                hold.minimumPressDuration = Self.spaceHold
                button.addGestureRecognizer(hold)
            default:
                button.addAction(UIAction { [weak self] _ in self?.pressed(key) }, for: .touchUpInside)
            }
        }

        @objc private func spaceHeld(_ hold: UILongPressGestureRecognizer) {
            guard hold.state == .began else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRowKey?(.keyboard)
        }

        private func pressed(_ key: Board.Key) {
            feedback()
            switch key {
            case .char(let char):
                onText?(Board.text(char, shift: shift))
                shift.typedLetter()
            case .space:
                onText?(" ")
            case .newline:
                onNewline?()
            case .ctrl:
                onCtrl?()
            case .shift:
                let now = Date()
                let double = lastShiftTap.map { now.timeIntervalSince($0) < Self.doubleTap } ?? false
                lastShiftTap = now
                shift.tapped(double: double)
            case .layer(let layer):
                board = layer
            case .backspace:
                onBackspace?()
            }
        }

        private func style(_ button: UIButton, for key: Board.Key) {
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .fixed
            config.background.cornerRadius = 8
            config.contentInsets = .zero
            config.titleLineBreakMode = .byClipping
            let special: Bool
            switch key {
            case .char(let char):
                special = false
                config.attributedTitle = Self.title(Board.text(char, shift: shift), size: 22, weight: .regular)
            case .space:
                special = false
                // Hold it to switch keyboards.
                config.attributedTitle = Self.title("space", size: 15, weight: .regular)
            case .newline:
                special = true
                config.attributedTitle = Self.title("return", size: 15, weight: .regular)
            case .layer(let layer):
                special = true
                config.attributedTitle = Self.title(Board.label(layer), size: 15, weight: .regular)
            case .ctrl:
                special = true
                config.attributedTitle = Self.title("ctrl", size: 15, weight: .regular)
            case .shift:
                special = shift == .off
                config.image = UIImage(systemName: shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
            case .backspace:
                special = true
                config.image = UIImage(systemName: "delete.left")
            }
            if config.preferredSymbolConfigurationForImage == nil {
                config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            }
            config.baseForegroundColor = LosttyUIColor.textPrimary
            let base = special ? LosttyUIColor.surface : LosttyUIColor.surfaceRaised
            config.baseBackgroundColor = button.isHighlighted ? LosttyUIColor.textPrimary.withAlphaComponent(0.22) : base
            if key == .ctrl && ctrlLatched {
                config.baseBackgroundColor = LosttyUIColor.accent
                config.baseForegroundColor = .white
            }
            button.configuration = config
            button.accessibilityLabel = Self.accessibilityName(key, shift: shift)
        }

        private static func title(_ text: String, size: CGFloat, weight: UIFont.Weight) -> AttributedString {
            var title = AttributedString(text)
            title.font = .systemFont(ofSize: size, weight: weight)
            return title
        }

        private static func accessibilityName(_ key: Board.Key, shift: Board.Shift) -> String {
            switch key {
            case .char(let char): Board.text(char, shift: shift)
            case .space: "Space, hold to switch keyboard"
            case .newline: "New line"
            case .ctrl: "Control"
            case .layer(let layer): Board.label(layer)
            case .shift: shift == .locked ? "Caps lock" : "Shift"
            case .backspace: "Delete"
            }
        }

        // MARK: The strip: esc, globe, send, flow

        /// The strip's keys: send (its own shiny look) and flow (styled as
        /// the return key above), each a little wider than return.
        private func buildStrip() {
            // send has its own look (SendKeyButton).
            send.addAction(UIAction { [weak self] _ in self?.feedback(); self?.onSend?() }, for: .touchUpInside)
            addSubview(send)
            for (button, title, action) in [
                (flowMode, "flow", { [weak self] in self?.onFlowMode?() }),
            ] as [(UIButton, String, () -> Void)] {
                button.accessibilityLabel = title
                button.configurationUpdateHandler = { button in
                    var config = UIButton.Configuration.filled()
                    config.cornerStyle = .fixed
                    config.background.cornerRadius = 8
                    config.contentInsets = .zero
                    config.attributedTitle = Self.title(title, size: 15, weight: .regular)
                    config.baseForegroundColor = LosttyUIColor.textPrimary
                    config.baseBackgroundColor = button.isHighlighted
                        ? LosttyUIColor.textPrimary.withAlphaComponent(0.22) : LosttyUIColor.surface
                    button.configuration = config
                }
                button.addAction(UIAction { [weak self] _ in self?.feedback(); action() }, for: .touchUpInside)
                addSubview(button)
            }
            // esc and the globe at the left, styled as 123 and ctrl.
            for (button, key) in [(esc, MobileInput.RowKey.esc), (globe, .keyboard)] {
                button.accessibilityLabel = key.accessibilityName
                button.configurationUpdateHandler = { button in
                    var config = UIButton.Configuration.filled()
                    config.cornerStyle = .fixed
                    config.background.cornerRadius = 8
                    config.contentInsets = .zero
                    if let symbol = key.symbol {
                        config.image = UIImage(systemName: symbol)
                        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                    } else {
                        config.attributedTitle = Self.title(key.label, size: 15, weight: .regular)
                    }
                    config.baseForegroundColor = LosttyUIColor.textPrimary
                    config.baseBackgroundColor = button.isHighlighted
                        ? LosttyUIColor.textPrimary.withAlphaComponent(0.22) : LosttyUIColor.surface
                    button.configuration = config
                }
                button.addAction(UIAction { [weak self] _ in self?.feedback(); self?.onRowKey?(key) }, for: .touchUpInside)
                addSubview(button)
            }
        }

        // MARK: Layout

        override func layoutSubviews() {
            super.layoutSubviews()
            let width = bounds.width
            handle?.frame = CGRect(x: 0, y: 0, width: width, height: Self.top)
            swipeFeedback.frame = bounds
            grabber.frame = CGRect(x: (width - 36) / 2, y: (Self.top - 5) / 2, width: 36, height: 5)
            let unit = (width - 2 * Self.side - 9 * Self.keyGap) / 10
            func keyWidth(_ w: Double) -> CGFloat { CGFloat(w) * unit + CGFloat(w - 1) * Self.keyGap }
            var y = Self.top
            for row in rows {
                let rowWidth = row.map { keyWidth($0.slot.width) }.reduce(0, +) + CGFloat(row.count - 1) * Self.keyGap
                var x = (width - rowWidth) / 2
                for (button, slot) in row {
                    let w = keyWidth(slot.width)
                    button.frame = CGRect(x: x, y: y, width: w, height: Self.keyHeight)
                    x += w + Self.keyGap
                }
                y += Self.keyHeight + Self.rowGap
            }
            // The strip, where iOS puts the globe and mic.
            let stripTop = y - Self.rowGap + Self.stripGap
            let stripKeyWidth = keyWidth(Board.returnWidth) + Self.sendExtra
            // esc and the globe, send and flow (each a little wider than
            // return), side by side, the row centered. esc and the globe with
            // the gap between them span send's width.
            let smallWidth = (stripKeyWidth - Self.keyGap) / 2
            let stripWidth = 2 * smallWidth + 2 * stripKeyWidth + 3 * Self.keyGap
            var x = (width - stripWidth) / 2
            for (button, w) in [(esc, smallWidth), (globe, smallWidth), (send, stripKeyWidth), (flowMode, stripKeyWidth)] {
                button.frame = CGRect(x: x, y: stripTop, width: w, height: Self.stripHeight)
                x += w + Self.keyGap
            }
        }

        // MARK: Feedback and repeat

        private func feedback() {
            UIDevice.current.playInputClick()
            tap.impactOccurred(intensity: 0.5)
        }

        private func startRepeating(_ action: @escaping () -> Void) {
            feedback()
            action()
            stopRepeating()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: Self.repeatDelay, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: Self.repeatInterval, repeats: true) { _ in action() }
            }
        }

        private func stopRepeating() {
            repeatTimer?.invalidate()
            repeatTimer = nil
        }
    }
}
#endif
