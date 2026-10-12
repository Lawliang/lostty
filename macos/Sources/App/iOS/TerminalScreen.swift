#if os(iOS)
import Combine
import GhosttyKit
import LosttyRemote
import SwiftUI

/// The open terminal's connection events, from its `RemoteSurfaceIO`
/// (delivered on the main thread).
@MainActor
final class TerminalLink {
    let events = PassthroughSubject<RemoteLinkStatus, Never>()
}

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking. When the session
/// ends from elsewhere, or the connection drops, an overlay over the dimmed
/// last screen says so.
struct TerminalScreen: View {
    let surfaceView: Ghostty.SurfaceView
    let io: RemoteSurfaceIO
    let link: TerminalLink
    @State private var session: RemoteSession
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmClose = false
    @State private var closeError: String?
    @State private var overlay: TerminalOverlay = .none
    /// Close Session from this screen is under way: its end is ours.
    @State private var closingHere = false
    /// The attach ended while the app was away: explain it on return.
    /// The value is whether input had just been sent.
    @State private var endWhileAway: Bool?
    @State private var renaming: RemoteSession?

    init(session: RemoteSession, surfaceView: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink) {
        _session = State(initialValue: session)
        self.surfaceView = surfaceView
        self.io = io
        self.link = link
    }

    private var title: String { SessionLabel.row(for: session, now: Date()).title }

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .opacity(overlay == .none ? 1 : 0.35)
        .allowsHitTesting(overlay == .none)
        .overlay {
            if overlay != .none {
                TerminalOverlayCard(overlay: overlay, title: title) { dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(LosttyTheme.motion, value: overlay)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .toolbar {
            ToolbarItem(placement: .principal) { TerminalTitle(name: title) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") { renaming = session }
                    Button("Close Session", role: .destructive) { confirmClose = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Close \(title)?", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("Close Session", role: .destructive) {
                closingHere = true
                Task {
                    if await store.kill(session) {
                        dismiss()
                    } else {
                        closingHere = false
                        closeError = store.message ?? "Couldn't close the session."
                    }
                }
            }
        } message: {
            Text("This ends the session on the Mac and closes its window there.")
        }
        .alert("Couldn't Close Session", isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeError ?? "")
        }
        .renameSession($renaming) { label in session.label = label }
        .onAppear { surfaceView.showKeyboard() }
        .onDisappear { store.terminalClosed(io) }
        .onReceive(link.events) { handle($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let typed = endWhileAway {
                endWhileAway = nil
                explainEnd(typedRecently: typed)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView {
                dismiss()
                Task { await store.terminalClosedItself(session) }
            }
        }
    }

    private func handle(_ status: RemoteLinkStatus) {
        if case .exited = status {
            guard !closingHere else { return }
            let typed = io.wroteRecently(within: SessionEnd.typedWindow)
            if scenePhase == .active {
                explainEnd(typedRecently: typed)
            } else {
                endWhileAway = typed
            }
            return
        }
        let next = overlay.after(status, now: Date())
        guard next != overlay else { return }
        let wasShowing = overlay != .none
        overlay = next
        if next == .none, wasShowing {
            surfaceView.showKeyboard()
        } else if next != .none {
            _ = surfaceView.resignFirstResponder()
        }
    }

    /// Asks the Mac why the session ended, then goes back to the list or
    /// says why over the dimmed screen.
    private func explainEnd(typedRecently: Bool) {
        Task {
            let probe = await store.endProbe(session)
            switch SessionEnd.decide(probe: probe, endedHere: closingHere, typedRecently: typedRecently) {
            case .backToList:
                dismiss()
            case .stillRunning:
                dismiss()
                await store.terminalClosedItself(session)
            case .closed(let reason):
                overlay = .closed(reason)
                _ = surfaceView.resignFirstResponder()
            }
        }
    }
}

/// The card over a dimmed terminal: why, which session, and (when closed,
/// or after 30 s of reconnecting) Back to Sessions.
private struct TerminalOverlayCard: View {
    let overlay: TerminalOverlay
    let title: String
    let back: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LosttyCard(padding: 20) {
                VStack(spacing: 12) {
                    if overlay.isReconnecting {
                        ProgressView().tint(LosttyTheme.accent)
                    }
                    Text(overlay.message ?? "")
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(title)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if overlay.offersBack(now: context.date) {
                        Button("Back to Sessions", action: back)
                            .buttonStyle(.lostty(.primary, fullWidth: true))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 340)
            .padding(LosttyTheme.margin)
        }
    }
}

/// The session's name in the terminal's top bar.
struct TerminalTitle: View {
    var name: String
    var body: some View {
        Text(name)
            .font(LosttyFont.mono(.headline, weight: .semibold))
            .foregroundStyle(LosttyTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
#endif
