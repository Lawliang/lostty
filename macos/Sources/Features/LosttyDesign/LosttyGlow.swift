import SwiftUI

extension View {
    /// A soft magenta glow behind a hero element: the axolotl on welcome,
    /// pairing, empty sessions and the Mac pairing sheet.
    func losttyGlow(diameter: CGFloat) -> some View {
        background {
            RadialGradient(colors: [LosttyTheme.accent.opacity(0.22), LosttyTheme.accent.opacity(0)],
                           center: .center, startRadius: 0, endRadius: diameter / 2)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
