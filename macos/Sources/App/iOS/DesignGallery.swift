#if os(iOS) && DEBUG
import LosttyRemote
import SwiftUI

/// Debug only: every Lostty screen in every state, with fake data, for
/// review. Open with launch argument `-LosttyDesignGallery YES`. Each entry
/// opens full screen (screens bring their own navigation stacks, which
/// can't be nested), with a Close button.
struct DesignGalleryScreen: View {
    private struct Entry: Identifiable {
        let id: String
        let screen: () -> AnyView
    }

    private static let paired = RemoteHostSettings(
        host: "laws-macbook-pro.tail278d1f.ts.net", port: 22, user: "lawliang",
        fallbackHost: "100.126.63.10", pairedAt: Date(timeIntervalSince1970: 1_791_000_000))
    private static let sessions = [
        RemoteSession(id: "$1", name: "lostty", surface: "A", owner: 1),
        RemoteSession(id: "$2", name: "ghostty-skins-experiments-with-a-very-long-name", surface: nil, owner: nil),
        RemoteSession(id: "$3", name: "home", surface: "B", owner: 1),
    ]

    @State private var shown: Entry?

    private var sections: [(String, [Entry])] {
        func entry(_ title: String, _ screen: @escaping () -> some View) -> Entry {
            Entry(id: title, screen: { AnyView(screen()) })
        }
        func pairing(_ title: String, _ phase: MobileStore.PairingPhase) -> Entry {
            entry(title) {
                NavigationStack { PairingScreen() }
                    .environmentObject(MobileStore.gallery(pairing: phase, settings: Self.paired))
            }
        }
        return [
            ("First run", [
                entry("Welcome") { WelcomeScreen(pair: {}, settings: {}) },
                entry("Welcome — large text") { WelcomeScreen(pair: {}, settings: {}).dynamicTypeSize(.xxxLarge) },
            ]),
            ("Sessions", [
                entry("Three sessions") {
                    SessionsScreen().environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired))
                },
                entry("Three sessions — large text") {
                    SessionsScreen().environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired))
                        .dynamicTypeSize(.xxxLarge)
                },
                entry("Message and Pair Again") {
                    SessionsScreen().environmentObject(MobileStore.gallery(
                        message: "Your Mac doesn't accept this phone anymore.", needsPairing: true, settings: Self.paired))
                },
                entry("Empty") {
                    SessionsScreen().environmentObject(MobileStore.gallery(message: MobileStore.noSessionsMessage, settings: Self.paired))
                },
            ]),
            ("Pairing", [
                pairing("Scan", .idle),
                pairing("Finding", .finding),
                pairing("Waiting for Allow", .waitingForAllow),
                pairing("Connecting", .testing),
                pairing("Failed, can retry", .failed(
                    "Your Mac allowed this phone, but Lostty couldn't reach it. \(MobileStore.tailscaleHint)", canRetryTest: true)),
                pairing("Failed", .failed("Your Mac declined. Try again from Phone Access.", canRetryTest: false)),
                pairing("Paired", .done),
            ]),
            ("Other", [
                entry("Settings") {
                    NavigationStack { SettingsScreen() }.environmentObject(MobileStore.gallery(settings: Self.paired))
                },
                entry("Terminal bar and key row (Ctrl latched)") { NavigationStack { TerminalBarPreview() } },
            ]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, entries in
                    Section(title) {
                        ForEach(entries) { entry in
                            Button(entry.id) { shown = entry }
                        }
                    }
                }
            }
            .navigationTitle("Design Gallery")
            .losttyScreen()
        }
        .fullScreenCover(item: $shown) { entry in
            entry.screen()
                .overlay(alignment: .bottomTrailing) {
                    Button("Close") { shown = nil }
                        .buttonStyle(.lostty(.secondary))
                        .padding(LosttyTheme.margin)
                }
        }
    }
}

/// The terminal's top bar over an empty terminal, and the key row with Ctrl
/// latched.
private struct TerminalBarPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            KeyRowPreview().frame(height: 52)
        }
        .toolbar { ToolbarItem(placement: .principal) { TerminalTitle(name: "lostty") } }
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
    }
}

private struct KeyRowPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> Ghostty.KeyRowView {
        let row = Ghostty.KeyRowView()
        row.setCtrl(true)
        return row
    }

    func updateUIView(_ view: Ghostty.KeyRowView, context: Context) {}
}
#endif
