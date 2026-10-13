#if os(iOS)
import UIKit

extension Ghostty {
    /// Lostty's keyboard's send key: the one action that matters, so it
    /// shines. A pink-to-violet gradient with a glossy top, a soft glow, a
    /// thin light edge, and a band of light that sweeps across every few
    /// seconds. Pressed, it dips and brightens.
    final class SendKeyButton: UIButton {
        static let cornerRadius: CGFloat = 8
        /// A sweep of light this often, taking `sweepDuration`.
        static let sweepEvery: TimeInterval = 3.2
        static let sweepDuration: TimeInterval = 0.9
        /// The far end of the gradient: a deep violet.
        static let violet = UIColor(red: 0x7B / 255, green: 0x3B / 255, blue: 0xF5 / 255, alpha: 1)

        private let fill = CAGradientLayer()
        private let gloss = CAGradientLayer()
        private let edge = CAShapeLayer()
        private let sweep = CAGradientLayer()
        private let sweepClip = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            fill.colors = [LosttyUIColor.accent.cgColor, Self.violet.cgColor]
            fill.startPoint = CGPoint(x: 0, y: 0)
            fill.endPoint = CGPoint(x: 1, y: 1)
            fill.cornerRadius = Self.cornerRadius
            fill.cornerCurve = .continuous

            gloss.colors = [UIColor.white.withAlphaComponent(0.32).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            gloss.startPoint = CGPoint(x: 0.5, y: 0)
            gloss.endPoint = CGPoint(x: 0.5, y: 0.55)

            edge.fillColor = UIColor.clear.cgColor
            edge.strokeColor = UIColor.white.withAlphaComponent(0.28).cgColor
            edge.lineWidth = 1

            sweep.colors = [UIColor.white.withAlphaComponent(0).cgColor,
                            UIColor.white.withAlphaComponent(0.35).cgColor,
                            UIColor.white.withAlphaComponent(0).cgColor]
            sweep.startPoint = CGPoint(x: 0, y: 0.5)
            sweep.endPoint = CGPoint(x: 1, y: 0.5)
            sweepClip.masksToBounds = true
            sweepClip.cornerRadius = Self.cornerRadius
            sweepClip.cornerCurve = .continuous
            sweepClip.addSublayer(sweep)

            // Under the label, bottom to top: fill, gloss, the sweep, the edge.
            layer.insertSublayer(fill, at: 0)
            layer.insertSublayer(gloss, above: fill)
            layer.insertSublayer(sweepClip, above: gloss)
            layer.insertSublayer(edge, above: sweepClip)
            // The glow, in the accent.
            layer.shadowColor = LosttyUIColor.accent.cgColor
            layer.shadowOpacity = 0.55
            layer.shadowRadius = 9
            layer.shadowOffset = .zero

            // "send ↑", drawn here, over every layer above.
            let text = UILabel()
            text.text = "send"
            text.font = .systemFont(ofSize: 16, weight: .semibold)
            text.textColor = .white
            let arrow = UIImageView(image: UIImage(systemName: "arrow.up",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
            arrow.tintColor = .white
            let content = UIStackView(arrangedSubviews: [text, arrow])
            content.axis = .horizontal
            content.alignment = .center
            content.spacing = 5
            content.isUserInteractionEnabled = false
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: centerXAnchor),
                content.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityLabel = "send"
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.frame = bounds
            gloss.frame = bounds
            let shape = UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath
            gloss.mask = Self.mask(shape, bounds)
            edge.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: Self.cornerRadius).cgPath
            layer.shadowPath = shape
            sweepClip.frame = bounds
            sweep.frame = CGRect(x: -bounds.width * 0.6, y: 0, width: bounds.width * 0.6, height: bounds.height)
            CATransaction.commit()
            if sweep.animation(forKey: "sweep") == nil { startSweeping() }
        }

        private static func mask(_ path: CGPath, _ bounds: CGRect) -> CAShapeLayer {
            let mask = CAShapeLayer()
            mask.frame = bounds
            mask.path = path
            return mask
        }

        /// The band of light, across and off, then a rest, again and again.
        /// Still under Reduce Motion.
        private func startSweeping() {
            guard !UIAccessibility.isReduceMotionEnabled, bounds.width > 0 else {
                sweep.removeAllAnimations()
                return
            }
            let across = CABasicAnimation(keyPath: "position.x")
            across.fromValue = -bounds.width * 0.3
            across.toValue = bounds.width * 1.3
            across.duration = Self.sweepDuration
            across.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let cycle = CAAnimationGroup()
            cycle.animations = [across]
            cycle.duration = Self.sweepEvery
            cycle.repeatCount = .infinity
            sweep.add(cycle, forKey: "sweep")
        }

        override var isHighlighted: Bool {
            didSet {
                UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
                    self.alpha = self.isHighlighted ? 0.85 : 1
                }
                layer.shadowOpacity = isHighlighted ? 0.9 : 0.55
            }
        }
    }
}
#endif
