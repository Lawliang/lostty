#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension Ghostty {
    /// A drag across Lostty's keyboard that becomes an arrow key. It only
    /// begins once the finger has clearly travelled (`startDistance`), so a
    /// tap that wanders a little is still a tap; once it begins, the key
    /// under the finger is cancelled.
    final class KeyboardSwipeRecognizer: UIGestureRecognizer {
        static let startDistance: CGFloat = 18

        private(set) var start: CGPoint = .zero
        private(set) var current: CGPoint = .zero
        private var touch: UITouch?

        var translation: CGPoint { CGPoint(x: current.x - start.x, y: current.y - start.y) }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            // One finger only: a second one ends it.
            guard touch == nil, let first = touches.first else {
                if state == .possible { state = .failed } else { state = .cancelled }
                return
            }
            touch = first
            start = first.location(in: view)
            current = start
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch, touches.contains(touch) else { return }
            current = touch.location(in: view)
            if state == .possible {
                if hypot(translation.x, translation.y) >= Self.startDistance { state = .began }
            } else {
                state = .changed
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch, touches.contains(touch) else { return }
            current = touch.location(in: view)
            state = state == .possible ? .failed : .ended
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            state = state == .possible ? .failed : .cancelled
        }

        override func reset() {
            super.reset()
            touch = nil
        }
    }

    /// What a swipe looks like while it happens: a light wash over the
    /// keyboard and a line following the finger; then, if it made an arrow,
    /// the arrow flicks out the way it went. Quick (about a fifth of a
    /// second), and a new swipe cuts the last one short, so arrows chain as
    /// fast as fingers go.
    final class KeyboardSwipeFeedback: UIView {
        static let duration: TimeInterval = 0.2

        private let wash = UIView()
        private let trace = CAShapeLayer()
        private let arrow = UIImageView()
        private var points: [CGPoint] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            wash.backgroundColor = UIColor.white.withAlphaComponent(0.07)
            wash.alpha = 0
            addSubview(wash)
            trace.strokeColor = LosttyUIColor.accent.cgColor
            trace.fillColor = UIColor.clear.cgColor
            trace.lineWidth = 5
            trace.lineCap = .round
            trace.lineJoin = .round
            trace.opacity = 0
            layer.addSublayer(trace)
            arrow.tintColor = LosttyUIColor.accent
            arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
            arrow.alpha = 0
            addSubview(arrow)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            wash.frame = bounds
            trace.frame = bounds
        }

        /// A swipe started: cut any last one short and show the wash.
        func begin(at start: CGPoint, to point: CGPoint) {
            stopAll()
            points = [start, point]
            draw()
            trace.opacity = 0.9
            UIView.animate(withDuration: 0.05, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.wash.alpha = 1
            }
        }

        func move(to point: CGPoint) {
            points.append(point)
            draw()
        }

        /// The swipe ended: the arrow it made flicks out (none for a
        /// too-short one), and everything fades.
        func finish(_ swipe: MobileInput.Board.Swipe?) {
            if let swipe {
                arrow.image = UIImage(systemName: swipe.symbol)
                arrow.sizeToFit()
                arrow.center = CGPoint(x: bounds.midX, y: bounds.midY)
                arrow.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                arrow.alpha = 1
                let push = CGAffineTransform(translationX: swipe.vector.dx * 28, y: swipe.vector.dy * 28)
                UIView.animate(withDuration: Self.duration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.arrow.transform = push.scaledBy(x: 1.1, y: 1.1)
                    self.arrow.alpha = 0
                }
            }
            UIView.animate(withDuration: Self.duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.wash.alpha = 0
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = trace.opacity
            fade.toValue = 0
            fade.duration = Self.duration
            trace.opacity = 0
            trace.add(fade, forKey: "fade")
        }

        private func draw() {
            let path = UIBezierPath()
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach(path.addLine)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trace.path = path.cgPath
            CATransaction.commit()
        }

        private func stopAll() {
            [wash, arrow].forEach { $0.layer.removeAllAnimations() }
            trace.removeAllAnimations()
            arrow.alpha = 0
            wash.alpha = 0
        }
    }
}
#endif
