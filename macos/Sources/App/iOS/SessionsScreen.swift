#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions, kept current while on screen; the
/// welcome screen while no Mac is set up.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)?
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var confirmKill: RemoteSession?
    @State private var renaming: RemoteSession?

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
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io, link: open.link)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { store.restartWatch() }) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $showPairing, onDismiss: { store.restartWatch() }) {
                NavigationStack { PairingScreen() }
            }
            .confirmationDialog(
                "Close \(confirmKill.map { SessionLabel.row(for: $0, now: Date()).title } ?? "")?",
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
            .renameSession($renaming)
            .onAppear {
                if path.isEmpty { store.listAppeared() }
                if store.pendingPairingLink != nil { showPairing = true }
            }
            .onChange(of: store.pendingPairingLink) { _, link in if link != nil { showPairing = true } }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty {
                    // Back from the terminal: drop it; the live list resumes.
                    open = nil
                    store.listAppeared()
                } else {
                    store.listDisappeared()
                }
            }
        }
    }

    private var sessionList: some View {
        // Once a minute, so "5m ago" stays true.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let groups = SessionLabel.ordered(store.sessions)
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
                ForEach(groups.open, id: \.id) { session in
                    row(session, now: context.date)
                }
                if !groups.notOpen.isEmpty {
                    Section {
                        ForEach(groups.notOpen, id: \.id) { session in
                            row(session, now: context.date).opacity(0.55)
                        }
                    } header: {
                        Text("Not open on Mac")
                            .font(LosttyFont.detail)
                            .foregroundStyle(LosttyTheme.textSecondary)
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
            .refreshable {
                await store.refresh()
                store.listAppeared()  // resumes a watch that stopped on an error
            }
        }
    }

    private func row(_ session: RemoteSession, now: Date) -> some View {
        Button {
            guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
            open = (session, terminal.view, terminal.io, terminal.link)
            path = ["terminal"]
        } label: {
            SessionRowView(row: SessionLabel.row(for: session, now: now))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
        .swipeActions {
            Button("Close", role: .destructive) { confirmKill = session }
            Button("Rename") { renaming = session }.tint(LosttyTheme.accent)
        }
    }

    /// No sessions and nothing else to say: the friendly empty state.
    private var showsEmptyState: Bool {
        store.sessions.isEmpty && !store.loading && store.message == MobileStore.noSessionsMessage
    }
}

/// One session: what it is, its project and kind, and Waiting/Working or
/// when it was last used.
private struct SessionRowView: View {
    let row: SessionRow

    var body: some View {
        LosttyCard(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if !row.statusText.isEmpty {
                    Text(row.statusText)
                        .font(row.status == .waiting ? LosttyFont.bodyEmphasis : LosttyFont.detail)
                        .foregroundStyle(row.status == .waiting ? LosttyTheme.accent : LosttyTheme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LosttyTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rename: one name everywhere (the Mac tab shows it too); blank goes back
/// to the automatic name. A failure goes to `failed`, or the list's message.
struct RenameSessionAlert: ViewModifier {
    @Binding var session: RemoteSession?
    /// The caller is attached to the session (see `MobileStore.rename`).
    var attached: Bool
    var renamed: (RemoteSession) -> Void
    var failed: ((String) -> Void)?
    @EnvironmentObject private var store: MobileStore
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Rename",
                isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } }),
                presenting: session
            ) { target in
                TextField("Name", text: $text)
                Button("Save") {
                    let typed = text
                    Task {
                        switch await store.rename(target, to: typed, attached: attached) {
                        case .renamed(let session): renamed(session)
                        case .failed(let text):
                            if let failed { failed(text) } else { store.message = text }
                        case .skipped: break
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Leave blank to use the automatic name.")
            }
            .onChange(of: session?.id) { _, id in
                if id != nil { text = session?.label ?? "" }
            }
    }
}

extension View {
    func renameSession(
        _ session: Binding<RemoteSession?>, attached: Bool = false,
        renamed: @escaping (RemoteSession) -> Void = { _ in }, failed: ((String) -> Void)? = nil
    ) -> some View {
        modifier(RenameSessionAlert(session: session, attached: attached, renamed: renamed, failed: failed))
    }
}

private struct EmptySessions: View {
    var body: some View {
        VStack(spacing: 10) {
            Axolotl(pose: .resting).frame(width: 104, height: 104).losttyGlow(diameter: 260)
                .padding(.bottom, 6)
            Text("Nothing running yet")
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text("Open Lostty on your Mac.")
                .font(LosttyFont.detail)
                .foregroundStyle(LosttyTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(LosttyTheme.margin)
    }
}
#endif
