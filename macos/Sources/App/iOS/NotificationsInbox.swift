#if os(iOS)
import LosttyRemote
import SwiftUI

/// The notes from 🔔, the iOS way: unread under New, read under Earlier,
/// each in its terminal's colors. Tapping one reads it and opens its
/// terminal, or starts its build's install; swipe right to mark it read
/// or unread, left to delete it for every phone; hold it for the same.
struct NotificationsInbox: View {
    /// Opens a terminal, as tapping its row in the list does.
    let openTerminal: (RemoteSession) -> Void
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                if store.shownNotes.isEmpty {
                    ContentUnavailableView(
                        "No Notifications", systemImage: "bell",
                        description: Text("Terminals waiting on you and new builds show up here."))
                } else {
                    List {
                        section("New", store.shownNotes.filter { !$0.read })
                        section("Earlier", store.shownNotes.filter(\.read))
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
                    Menu {
                        Button("Mark All Read", systemImage: "envelope.open") { store.markAllNotesRead() }
                            .disabled(store.unreadNotes == 0)
                        Button("Clear Read", systemImage: "trash", role: .destructive) { store.clearReadNotes() }
                            .disabled(!store.shownNotes.contains(where: \.read))
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ notes: [LosttyNote]) -> some View {
        if !notes.isEmpty {
            Section {
                ForEach(notes) { note in
                    let ended = hasEnded(note)
                    Button { tap(note) } label: { NoteRow(note: note, ended: ended) }
                        .buttonStyle(.plain)
                        .disabled(ended)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: 5, leading: LosttyTheme.margin, bottom: 5, trailing: LosttyTheme.margin))
                        .swipeActions(edge: .leading) { readButton(note) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(note) }
                        .contextMenu {
                            if !ended {
                                Button(note.kind == .build ? "Install" : "Open", systemImage: "arrow.up.forward.app") {
                                    tap(note)
                                }
                            }
                            readButton(note)
                            deleteButton(note)
                        }
                }
            } header: {
                Text(title)
                    .font(LosttyFont.detail.weight(.semibold))
                    .foregroundStyle(LosttyTheme.textSecondary)
            }
        }
    }

    private func readButton(_ note: LosttyNote) -> some View {
        Button(note.read ? "Mark Unread" : "Mark Read", systemImage: note.read ? "envelope.badge" : "envelope.open") {
            if note.read { store.markNotesUnread([note.id]) } else { store.markNotesRead([note.id]) }
        }
        .tint(LosttyTheme.accent)
    }

    private func deleteButton(_ note: LosttyNote) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { store.deleteNotes([note.id]) }
            .tint(.red)
    }

    /// A waiting note whose terminal is gone: nothing to open.
    private func hasEnded(_ note: LosttyNote) -> Bool {
        note.kind == .waiting && !store.sessions.contains { $0.id == note.sessionID }
    }

    private func tap(_ note: LosttyNote) {
        store.markNotesRead([note.id])
        switch note.kind {
        case .waiting:
            guard let session = store.sessions.first(where: { $0.id == note.sessionID }) else { return }
            dismiss()
            openTerminal(session)
        case .build:
            if let url = note.build.flatMap({ URL(string: $0.installURL) }) { openURL(url) }
        }
    }
}

/// A note as its terminal's row looks: the skin's colors and texture, a
/// dot while unread, and "Ended" once its terminal is gone.
struct NoteRow: View {
    let note: LosttyNote
    var ended = false
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
                    if ended {
                        Text("Ended")
                            .font(LosttyFont.detail.weight(.semibold))
                            .foregroundStyle(colors.secondary)
                    } else {
                        Text(note.updated, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(LosttyFont.detail)
                            .foregroundStyle(colors.secondary)
                    }
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
        .opacity(ended ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityValue(ended ? "Ended" : note.read ? "" : "Unread")
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
            .background(Color.red, in: Capsule())
            .accessibilityHidden(true)
    }
}
#endif
