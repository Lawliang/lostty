#if os(iOS)
import LosttyRemote
import SwiftUI

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking.
struct TerminalScreen: View {
    let session: RemoteSession
    let surfaceView: Ghostty.SurfaceView
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClose = false

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Close Session", role: .destructive) { confirmClose = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog(
            "Close \(session.name)?", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("Close Session", role: .destructive) {
                Task {
                    await store.kill(session)
                    dismiss()
                }
            }
        } message: {
            Text("This ends the session on the Mac and closes its window there.")
        }
        .onAppear { surfaceView.showKeyboard() }
        .onDisappear { store.terminalClosed() }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView { dismiss() }
        }
    }
}
#endif
