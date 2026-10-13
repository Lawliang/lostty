#if os(macOS)
import SwiftUI

/// A pane's trace with every default filled in, ready to draw.
struct ResolvedTrace: Equatable {
    var style: BuiltinTrace
    var color: RGB
    var color2: RGB
    var speed: Double
    var length: Double

    /// Lostty's hologram pink and cyan, for panes with no skin.
    static let unskinnedColor = RGB(hex: "#ff7ad9")!
    static let unskinnedColor2 = RGB(hex: "#7af0ff")!

    /// nil when traces are off (`[defaults] trace = false`, `trace = "none"`).
    static func resolve(skin: Skin?, enabled: Bool) -> ResolvedTrace? {
        guard enabled else { return nil }
        guard let skin else {
            return ResolvedTrace(style: .beam, color: unskinnedColor, color2: unskinnedColor2,
                                 speed: SkinTrace().speed, length: SkinTrace().length)
        }
        let trace = skin.trace ?? SkinTrace()
        guard !trace.disabled else { return nil }
        let color = trace.color ?? skin.accent
        return ResolvedTrace(
            style: trace.style ?? .beam,
            color: color,
            color2: trace.color2 ?? skin.accent2 ?? color.mixed(with: .white, amount: 0.4),
            speed: trace.speed,
            length: trace.length)
    }
}

#endif
