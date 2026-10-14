#if os(iOS)
import LosttyRemote
import SwiftUI

/// The notes from 🔔: newest first, each in its terminal's colors. Tapping
/// one reads it and opens its terminal, or starts its build's install;
/// swiping one away deletes it for every phone.
struct NotificationsInbox: View {
    /// Opens a terminal, as tapping its row in the list does.
    let openTerminal: (RemoteSession) -> Void
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var ended: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.shownNotes.isEmpty {
                    ContentUnavailableView(
                        "No Notifications", systemImage: "bell",
                        description: Text("Terminals waiting on you and new builds show up here."))
                } else {
                    List {
                        ForEach(store.shownNotes) { note in
                            Button { tap(note) } label: { NoteRow(note: note) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 5, leading: LosttyTheme.margin, bottom: 5, trailing: LosttyTheme.margin))
                        }
                        .onDelete { offsets in
                            let shown = store.shownNotes
                            store.deleteNotes(offsets.map { shown[$0].id })
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .losttyScreen()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Mark All Read") { store.markAllNotesRead() }
                        .disabled(store.unreadNotes == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert(
                "That terminal has ended",
                isPresented: Binding(get: { ended != nil }, set: { if !$0 { ended = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ended ?? "")
            }
        }
    }

    private func tap(_ note: LosttyNote) {
        store.markNotesRead([note.id])
        switch note.kind {
        case .waiting:
            guard let session = store.sessions.first(where: { $0.id == note.sessionID }) else {
                ended = note.title
                return
            }
            dismiss()
            openTerminal(session)
        case .build:
            if let url = note.build.flatMap({ URL(string: $0.installURL) }) { openURL(url) }
        }
    }
}

/// A note as its terminal's row looks: the skin's colors and texture, a
/// dot while unread, dimmed once read.
private struct NoteRow: View {
    let note: LosttyNote
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let skin = note.skin.flatMap(SessionSkin.init(encoded:))
        let colors = RowColors(skin: skin)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.kind == .waiting ? "hand.raised" : "arrow.down.app")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.prompt)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title)
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(colors.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(note.updated, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(LosttyFont.detail)
                        .foregroundStyle(colors.secondary)
                }
                Text(note.body)
                    .font(LosttyFont.detail)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(2)
            }
            if !note.read {
                Circle().fill(colors.flash).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                colors.background
                if let skin, let texture = skin.texture, let tile = TextureTile.image(for: skin, displayScale: displayScale) {
                    Image(decorative: tile, scale: displayScale)
                        .resizable(resizingMode: .tile)
                        .opacity(TerminalLook.textureOpacity(texture))
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(colors.border, lineWidth: 1))
        .opacity(note.read ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityValue(note.read ? "" : "Unread")
    }
}

/// 🔔's unread count.
struct NoteBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(LosttyTheme.accent, in: Capsule())
            .accessibilityHidden(true)
    }
}
#endif
