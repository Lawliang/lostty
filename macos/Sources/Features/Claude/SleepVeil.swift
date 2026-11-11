#if os(macOS)
import SwiftUI

/// The light veil over a sleeping pane (`PaneSleep`). Clicks pass through
/// to the pane, and a click there wakes it.
struct SleepVeil: View {
    let surfaceID: UUID
    @ObservedObject private var sleep = PaneSleep.shared

    var body: some View {
        let veiled = sleep.isVeiled(surfaceID)
        ZStack {
            if veiled { Color.white.opacity(0.14) }
        }
        .animation(.easeOut(duration: 0.25), value: veiled)
        .allowsHitTesting(false)
    }
}
#endif
