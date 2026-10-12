#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions by project name; the welcome screen while
/// no Mac is set up.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO)?
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var confirmKill: RemoteSession?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.settings.remoteHost == nil {
                    WelcomeScreen(pair: { showPairing = true }, settings: { showSettings = true })
                } else {
                    sessionList
                }
            }
            .navigationTitle("Lostty")
            .losttyScreen()
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").foregroundStyle(LosttyTheme.textSecondary)
                }
            }
            .navigationDestination(for: String.self) { _ in
                if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await refreshIfSetUp() } }) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $showPairing, onDismiss: { Task { await refreshIfSetUp() } }) {
                NavigationStack { PairingScreen() }
            }
            .confirmationDialog(
                "Close \(confirmKill?.name ?? "")?",
                isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } }),
                titleVisibility: .visible,
                presenting: confirmKill
            ) { session in
                Button("Close Session", role: .destructive) {
                    Task { await store.kill(session) }
                }
            } message: { _ in
                Text("This ends the session on the Mac and closes its window there.")
            }
            .task { await refreshIfSetUp() }
            .onAppear { if store.pendingPairingLink != nil { showPairing = true } }
            .onChange(of: store.pendingPairingLink) { _, link in if link != nil { showPairing = true } }
            .onChange(of: path) { _, newPath in
                // Back from the terminal: drop it, and refresh the list.
                if newPath.isEmpty {
                    open = nil
                    Task { await refreshIfSetUp() }
                }
            }
        }
    }

    private var sessionList: some View {
        List {
            if let message = store.message, !showsEmptyState {
                LosttyCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                        if store.needsPairing {
                            Button("Pair Again") { showPairing = true }.buttonStyle(.lostty(.primary))
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
            }
            ForEach(store.sessions, id: \.id) { session in
                Button {
                    guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
                    open = (session, terminal.view, terminal.io)
                    path = ["terminal"]
                } label: {
                    LosttyCard(padding: 14) {
                        HStack(spacing: 12) {
                            Text(session.name)
                                .font(LosttyFont.mono(.callout, weight: .medium))
                                .foregroundStyle(LosttyTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if session.owner != nil {
                                Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)
                                    .accessibilityLabel("Open on the Mac")
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LosttyTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
                .swipeActions {
                    Button("Close", role: .destructive) { confirmKill = session }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if showsEmptyState {
                // Let pulls reach the list underneath (pull to refresh).
                EmptySessions().allowsHitTesting(false)
            } else if store.loading && store.sessions.isEmpty {
                ProgressView().tint(LosttyTheme.accent)
            }
        }
        .refreshable { await store.refresh() }
    }

    /// No sessions and nothing else to say: the friendly empty state.
    private var showsEmptyState: Bool {
        store.sessions.isEmpty && !store.loading && store.message == MobileStore.noSessionsMessage
    }

    private func refreshIfSetUp() async {
        if store.settings.remoteHost != nil { await store.refresh() }
    }
}

private struct EmptySessions: View {
    var body: some View {
        ZStack {
            BlueprintBackground()
            VStack(spacing: 16) {
                Axolotl(pose: .resting).frame(width: 120, height: 120)
                Text("Nothing running yet. Open Lostty on your Mac.")
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(LosttyTheme.margin)
        }
    }
}
#endif
