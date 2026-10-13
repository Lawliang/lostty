import SwiftUI

/// A trace's two colors as SwiftUI colors.
struct TraceColors {
    let primary: RGB
    let secondary: RGB

    init(primary: RGB, secondary: RGB) {
        self.primary = primary
        self.secondary = secondary
    }

    #if os(macOS)
    init(_ trace: ResolvedTrace) {
        self.init(primary: trace.color, secondary: trace.color2)
    }
    #endif

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
