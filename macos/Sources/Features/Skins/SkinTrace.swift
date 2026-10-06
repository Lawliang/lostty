#if os(macOS)
import Foundation

/// Built-in Claude trace styles (spec §3.1). One per preset, plus `beam`.
enum BuiltinTrace: String, CaseIterable {
    case beam, comet, sunset, datastream, sonar, ember, bubbles
    case bolt, tide, blade, petal, arrow, tempest
}

/// A skin's trace settings, from a preset or skins.toml (spec §3.2).
struct SkinTrace: Hashable {
    /// nil = not chosen: a shadowed preset's style, otherwise `beam`.
    var style: BuiltinTrace? = nil
    /// `trace = "none"`.
    var disabled = false
    /// nil = the skin's accent.
    var color: RGB? = nil
    /// nil = the skin's accent2, else the primary lightened.
    var color2: RGB? = nil
    /// Multiplier, 0.25...4.
    var speed: Double = 1
    /// Tail length as a share of the perimeter, 0.05...0.5.
    var length: Double = 0.18

    static let speedRange: ClosedRange<Double> = 0.25...4
    static let lengthRange: ClosedRange<Double> = 0.05...0.5
}
#endif
