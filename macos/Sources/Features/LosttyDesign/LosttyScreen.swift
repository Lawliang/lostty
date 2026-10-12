#if os(iOS)
import SwiftUI

extension View {
    /// A Lostty screen: near-black background and a matching navigation bar.
    func losttyScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(LosttyTheme.background.ignoresSafeArea())
            .toolbarBackground(LosttyTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
#endif
