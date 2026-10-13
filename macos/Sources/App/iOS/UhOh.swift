#if os(iOS)
import SwiftUI

/// The app's "something's wrong" state, centered: the axolotl, "Uh oh!",
/// what's wrong in a line, an optional detail, and what to do about it.
struct UhOh<Actions: View>: View {
    var headline: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Axolotl(pose: .resting)
                .frame(width: 104, height: 104)
                .losttyGlow(diameter: 260)
                .padding(.bottom, 8)
            Text("Uh oh!")
                .font(LosttyFont.largeTitle)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text(headline)
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textPrimary)
            if let detail {
                Text(detail)
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) { actions }
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .padding(LosttyTheme.margin)
    }
}
#endif
