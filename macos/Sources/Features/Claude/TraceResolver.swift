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

/// A trace's two colors as SwiftUI colors.
struct TraceColors {
    let primary: RGB
    let secondary: RGB

    init(primary: RGB, secondary: RGB) {
        self.primary = primary
        self.secondary = secondary
    }

    init(_ trace: ResolvedTrace) {
        self.init(primary: trace.color, secondary: trace.color2)
    }

    var head: Color { Self.color(primary) }
    var tail: Color { Self.color(secondary) }

    /// 0 = secondary (tail end), 1 = primary (head).
    func blend(_ t: Double) -> Color { Self.color(secondary.mixed(with: primary, amount: min(1, max(0, t)))) }

    /// The core's color: the blend, heating to near white at the head.
    func hot(_ t: Double) -> Color {
        let c = min(1, max(0, t))
        return Self.color(secondary.mixed(with: primary, amount: c).mixed(with: .white, amount: 0.85 * pow(c, 4)))
    }

    func swapped() -> TraceColors { TraceColors(primary: secondary, secondary: primary) }

    static func color(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
#endif
