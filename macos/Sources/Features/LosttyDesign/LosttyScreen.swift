#if os(iOS)
import SwiftUI

extension View {
    /// A Lostty screen: near-black background. The navigation bar is left to
    /// the system: on iOS 26, `toolbarBackground`/`toolbarColorScheme` hide
    /// the navigation title.
    func losttyScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(LosttyTheme.background.ignoresSafeArea())
    }
}
#endif
