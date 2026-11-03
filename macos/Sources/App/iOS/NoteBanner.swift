#if os(iOS)
import LosttyRemote
import SwiftUI

/// A note that arrives while the app is open drops in from the top, in
/// its terminal's colors: tap it to open it, swipe it up to dismiss it,
/// or it goes by itself. None for the terminal already open.
struct NoteBanner: ViewModifier {
    /// The terminal on screen, if one is.
    let openSessionID: String?
    let open: (LosttyNote) -> Void
    @EnvironmentObject private var store: MobileStore
    @State private var note: LosttyNote?
    /// Notes updated before this were seen, or came before the app opened.
    @State private var since = Date()
    @State private var drag: CGFloat = 0
    @State private var hiding: Task<Void, Never>?

    static let shownFor: Duration = .seconds(5)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let note {
                    NoteRow(note: note)
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                        .padding(.horizontal, LosttyTheme.margin)
                        .offset(y: min(drag, 0))
                        .onTapGesture {
                            hide()
                            open(note)
                        }
                        .gesture(DragGesture()
                            .onChanged { drag = $0.translation.height }
                            .onEnded { value in
                                if value.translation.height < -30 {
                                    hide()
                                } else {
                                    withAnimation(LosttyTheme.motion) { drag = 0 }
                                }
                            })
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Dismiss") { hide() }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: note?.id)
            .onChange(of: store.shownNotes) { _, notes in arrived(notes) }
    }

    private func arrived(_ notes: [LosttyNote]) {
        let fresh = notes.filter { note in
            !note.read && note.updated > since && !(note.kind == .waiting && note.sessionID == openSessionID)
        }
        since = max(since, notes.map(\.updated).max() ?? since)
        guard let newest = fresh.max(by: { $0.updated < $1.updated }) else { return }
        drag = 0
        note = newest
        hiding?.cancel()
        hiding = Task { @MainActor in
            try? await Task.sleep(for: Self.shownFor)
            if !Task.isCancelled { note = nil }
        }
    }

    private func hide() {
        hiding?.cancel()
        note = nil
    }
}
#endif
