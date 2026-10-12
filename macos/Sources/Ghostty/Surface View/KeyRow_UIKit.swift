#if os(iOS)
import UIKit

extension Ghostty {
    /// Lostty Mobile: the key row above the keyboard. Ctrl latches for the
    /// next key and shows it.
    final class KeyRowView: UIInputView {
        var onKey: ((MobileInput.RowKey) -> Void)?
        private var ctrlButton: UIButton?

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
            allowsSelfSizing = true
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            for key in MobileInput.RowKey.allCases {
                let button = UIButton(type: .system)
                button.setTitle(key.label, for: .normal)
                button.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                button.titleLabel?.minimumScaleFactor = 0.6
                button.backgroundColor = LosttyUIColor.surfaceRaised
                button.setTitleColor(LosttyUIColor.textPrimary, for: .normal)
                button.layer.cornerRadius = 8
                button.layer.cornerCurve = .continuous
                button.accessibilityLabel = key.rawValue
                button.addAction(UIAction { [weak self] _ in self?.onKey?(key) }, for: .touchUpInside)
                if key == .ctrl { ctrlButton = button }
                stack.addArrangedSubview(button)
            }
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
                heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        /// Shows whether Ctrl is latched; a light tap when it latches.
        func setCtrl(_ on: Bool) {
            ctrlButton?.backgroundColor = on ? LosttyUIColor.accent : LosttyUIColor.surfaceRaised
            ctrlButton?.setTitleColor(on ? .white : LosttyUIColor.textPrimary, for: .normal)
            if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }
}
#endif
