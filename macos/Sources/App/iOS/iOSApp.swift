import SwiftUI
import GhosttyKit

@main
struct Ghostty_iOSApp: App {
    @StateObject private var ghostty_app: Ghostty.App
    // Lostty Mobile: sessions, settings, key and reconnects.
    @StateObject private var store = MobileStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            preconditionFailure("Initialize ghostty backend failed")
        }
        // Before any terminal looks up its font.
        BundledTerminalFonts.register()
        _ghostty_app = StateObject(wrappedValue: Ghostty.App())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Unused for a while: a still screen in place of everything.
                if store.resting {
                    RestingScreen()
                } else {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "LosttyDesignGallery") {
                        DesignGalleryScreen()
                    } else {
                        MainTabs()
                    }
                    #else
                    MainTabs()
                    #endif
                }
            }
            .background(TouchWatcher { store.used() })
            .environmentObject(ghostty_app)
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(LosttyTheme.accent)
            // The Mac's pairing code scanned with the Camera app.
            .onOpenURL { store.openPairingLink($0) }
        }
        .onChange(of: scenePhase) { _, phase in store.scenePhaseChanged(phase) }
    }
}

struct iOS_GhosttyTerminal: View {
    @EnvironmentObject private var ghostty_app: Ghostty.App

    var body: some View {
        ZStack {
            // Make sure that our background color extends to all parts of the screen
            Color(ghostty_app.config.backgroundColor).ignoresSafeArea()

            Ghostty.Terminal()
        }
    }
}

struct iOS_GhosttyInitView: View {
    @EnvironmentObject private var ghostty_app: Ghostty.App

    var body: some View {
        VStack {
            Image("LosttyIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 96)
            Text("Lostty")
            Text("State: \(ghostty_app.readiness.rawValue)")
        }
        .padding()
    }
}
