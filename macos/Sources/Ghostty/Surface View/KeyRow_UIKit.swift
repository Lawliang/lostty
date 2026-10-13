#if os(iOS)
import UIKit

extension Ghostty {
    /// Lostty Mobile: the row over iOS's keyboard (when the space bar's hold
    /// switched to it): esc, and the globe back to Lostty's keyboard, which
    /// iOS's has no way to. Lostty's own keyboard has no row above it.
    final class KeyRowView: UIInputView {
        static let rowHeight: CGFloat = 56
        static let keyGap: CGFloat = 6

        var onKey: ((MobileInput.RowKey) -> Void)?
        private let tap = UIImpactFeedbackGenerator(style: .light)

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.rowHeight), inputViewStyle: .keyboard)
            allowsSelfSizing = true
            let keys = UIStackView(arrangedSubviews: [MobileInput.RowKey.esc, .keyboard].map(button))
            keys.axis = .horizontal
            keys.distribution = .fillEqually
            keys.spacing = Self.keyGap
            keys.translatesAutoresizingMaskIntoConstraints = false
            addSubview(keys)
            NSLayoutConstraint.activate([
                // From the screen's edges: the same as between keys.
                keys.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.keyGap),
                keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.keyGap),
                keys.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                keys.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
                heightAnchor.constraint(equalToConstant: Self.rowHeight),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private func button(_ key: MobileInput.RowKey) -> UIButton {
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .fixed
            config.background.cornerRadius = 10
            config.contentInsets = .zero
            if let symbol = key.symbol {
                config.image = UIImage(systemName: symbol)
                config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            } else {
                var title = AttributedString(key.label)
                title.font = .systemFont(ofSize: 13, weight: .semibold)
                config.attributedTitle = title
            }
            let button = UIButton(configuration: config)
            button.accessibilityLabel = key.accessibilityName
            // Darker while pressed.
            button.configurationUpdateHandler = { button in
                var config = button.configuration
                config?.baseForegroundColor = LosttyUIColor.textPrimary
                config?.baseBackgroundColor = button.isHighlighted
                    ? LosttyUIColor.textPrimary.withAlphaComponent(0.22) : LosttyUIColor.surfaceRaised
                button.configuration = config
            }
            button.addAction(UIAction { [weak self] _ in
                self?.tap.impactOccurred(intensity: 0.6)
                self?.onKey?(key)
            }, for: .touchUpInside)
            return button
        }
    }
}
#endif
