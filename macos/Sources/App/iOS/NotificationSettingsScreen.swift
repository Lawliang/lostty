#if os(iOS)
import LosttyRemote
import SwiftUI

/// Settings → Notifications: a switch per kind, for the inbox under 🔔
/// (and the banner while the app is open). Push comes with stage 2; until
/// then on means in-app only.
struct NotificationSettingsScreen: View {
    @EnvironmentObject private var store: MobileStore

    var body: some View {
        Form {
            ForEach(LosttyNote.Kind.allCases, id: \.self) { kind in
                Section {
                    Toggle(kind.settingsTitle, isOn: Binding(
                        get: { store.noteSettings[kind] != .off },
                        set: { store.setDelivery($0 ? .wave : .off, for: kind) }))
                        .tint(LosttyTheme.accent)
                } footer: {
                    Text(kind.settingsDetail)
                }
                .listRowBackground(LosttyTheme.surface)
            }
        }
        .losttyScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
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
#endif
