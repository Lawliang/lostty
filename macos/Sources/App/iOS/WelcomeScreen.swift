#if os(iOS)
import SwiftUI

/// First run: nothing paired or typed yet.
struct WelcomeScreen: View {
    var pair: () -> Void
    var settings: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Axolotl(pose: .resting)
                        .frame(width: 160, height: 160)
                        .losttyGlow(diameter: 360)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Text("Open your Mac's Lostty sessions from here.")
                        .font(LosttyFont.largeTitle)
                        .foregroundStyle(LosttyTheme.textPrimary)
                    VStack(alignment: .leading, spacing: LosttyTheme.gap) {
                        step(1, "Install Tailscale on your Mac and this iPhone, signed into the same account.")
                        step(2, "On your Mac, open Lostty → Phone Access.")
                        step(3, "Tap Pair with Mac.")
                    }
                }
                .padding(LosttyTheme.margin)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Button("Pair with Mac", action: pair).buttonStyle(.lostty(.primary, fullWidth: true))
                    Button("Set Up by Hand", action: settings).buttonStyle(.lostty(.quiet))
                }
                .padding(LosttyTheme.margin)
                .background(LosttyTheme.background.opacity(0.9))
            }
        }
        .background(LosttyTheme.background.ignoresSafeArea())
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(LosttyFont.mono(.footnote, size: 13, weight: .semibold))
                .foregroundStyle(LosttyTheme.accent)
                .frame(width: 26, height: 26)
                .background(LosttyTheme.accentSoft, in: Circle())
            Text(text)
                .font(LosttyFont.body)
                .foregroundStyle(LosttyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
