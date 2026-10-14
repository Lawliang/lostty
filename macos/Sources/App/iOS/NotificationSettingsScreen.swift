#if os(iOS)
import LosttyRemote
import SwiftUI

/// Settings → Notifications: per kind, Off, Notify (in-app only: the inbox
/// under 🔔), or Notify + Push to iOS. Push comes with stage 2; until then
/// it isn't offered.
struct NotificationSettingsScreen: View {
    @EnvironmentObject private var store: MobileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(LosttyNote.Kind.allCases, id: \.self) { kind in
                    LosttyCard(padding: 0) {
                        NoteKindRow(
                            kind: kind,
                            delivery: Binding(get: { store.noteSettings[kind] }, set: { store.setDelivery($0, for: kind) }))
                    }
                }
            }
            .padding(LosttyTheme.margin)
        }
        .losttyScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NoteKindRow: View {
    let kind: LosttyNote.Kind
    @Binding var delivery: NoteDelivery

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.settingsTitle).font(LosttyFont.body).foregroundStyle(LosttyTheme.textPrimary)
                Text(kind.settingsDetail).font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Picker(kind.settingsTitle, selection: $delivery) {
                // Push comes with stage 2; until then it isn't offered.
                ForEach(NoteDelivery.allCases.filter { $0 != .push }, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(LosttyTheme.textSecondary)
            // One line: the choice's whole name; the description wraps instead.
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }
}

extension LosttyNote.Kind {
    var settingsTitle: String {
        switch self {
        case .waiting: "Waiting on You"
        case .build: "New Builds"
        }
    }

    var settingsDetail: String {
        switch self {
        case .waiting: "When Claude asks you something in a terminal."
        case .build: "When a build is ready to install over Tailscale."
        }
    }
}

extension NoteDelivery {
    var title: String {
        switch self {
        case .off: "Off"
        case .wave: "Notify (in-app only)"
        case .push: "Notify + Push to iOS"
        }
    }
}
#endif
