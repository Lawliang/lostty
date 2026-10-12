#if os(iOS)
import SwiftUI

/// First run: nothing paired or typed yet.
struct WelcomeScreen: View {
    var pair: () -> Void
    var settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Open your Mac's Lostty sessions from here.").font(.title2.bold())
            Label("Install Tailscale on your Mac and this iPhone, signed into the same account.", systemImage: "1.circle")
            Label("On your Mac, open Lostty → Phone Access.", systemImage: "2.circle")
            Label("Tap Pair with Mac.", systemImage: "3.circle")
            Button(action: pair) {
                Text("Pair with Mac").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Advanced Setup", action: settings).font(.footnote)
        }
        .padding()
    }
}
#endif
