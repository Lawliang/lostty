#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking.
struct TerminalScreen: View {
    let session: RemoteSession
    let surfaceView: Ghostty.SurfaceView
    let io: RemoteSurfaceIO
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClose = false
    @State private var closeError: String?

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .toolbar {
            ToolbarItem(placement: .principal) { TerminalTitle(name: session.name) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Close Session", role: .destructive) { confirmClose = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Close \(session.name)?", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("Close Session", role: .destructive) {
                Task {
                    if await store.kill(session) {
                        dismiss()
                    } else {
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
        .onAppear { surfaceView.showKeyboard() }
        .onDisappear { store.terminalClosed(io) }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView {
                dismiss()
                Task { await store.terminalClosedItself(session) }
            }
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
