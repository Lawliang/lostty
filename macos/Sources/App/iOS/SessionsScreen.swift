#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions by project name.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO)?
    @State private var showSettings = false
    @State private var confirmKill: RemoteSession?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let message = store.message {
                    Text(message).foregroundStyle(.secondary)
                }
                ForEach(store.sessions, id: \.id) { session in
                    Button {
                        guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
                        open = (session, terminal.view, terminal.io)
                        path = ["terminal"]
                    } label: {
                        HStack {
                            Text(session.name).font(.body.monospaced())
                            Spacer()
                            if session.owner != nil {
                                Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                                    .accessibilityLabel("Open on the Mac")
                            }
                        }
                    }
                    .swipeActions {
                        Button("Close", role: .destructive) { confirmKill = session }
                    }
                }
            }
            .overlay { if store.loading && store.sessions.isEmpty { ProgressView() } }
            .refreshable { await store.refresh() }
            .navigationTitle("Lostty")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .navigationDestination(for: String.self) { _ in
                if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await store.refresh() } }) {
                NavigationStack { SettingsScreen() }
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
            .task { await store.refresh() }
            .onChange(of: path) { _, newPath in
                // Back from the terminal: drop it, and refresh the list.
                if newPath.isEmpty {
                    open = nil
                    Task { await store.refresh() }
                }
            }
        }
    }
}
#endif
