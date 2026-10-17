#if os(macOS)
import SwiftUI

/// Lostty Settings: preferences that live in the app rather than the
/// config file.
struct SettingsView: View {
    @ObservedObject var sidebar: SidebarPreferences
    @ObservedObject var observer: ObserverPreferences
    @ObservedObject var handoff: ContextHandoffPreferences
    /// The Mascot section is for the beta, the only build with the mascot.
    var showsMascot = LosttyChannel.current.showsMascot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Sidebar") {
                    Toggle("Automatically hide sidebar", isOn: $sidebar.autoHide)
                    Text("Shows when you move the pointer to the window's right edge. "
                         + "Stays open while an app is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsMascot {
                    Section("Mascot") {
                        Toggle("Summarize turns in the background", isOn: $observer.background)
                        Text("After each turn, Claude Haiku (or Codex, or Apple Intelligence) updates what the "
                             + "mascot tells you when you tap it, using your own subscription. "
                             + "Off, it summarizes only when you tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Hand off long conversations", isOn: $handoff.enabled)
                        Picker("Hand off after", selection: $handoff.limit) {
                            ForEach(ContextHandoffPreferences.limits, id: \.self) { limit in
                                Text(ContextHandoffDirective.k(limit)).tag(limit)
                            }
                        }
                        .disabled(!handoff.enabled)
                        Text("Past this, Claude hands off at its next clean break and Lostty starts a fresh "
                             + "window from the handoff, in terminals open on this Mac. On 200k models: "
                             + "\(ContextHandoffDirective.k(ContextHandoffPolicy.limit(setting: handoff.limit, size: 200_000))).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Text("Terminal settings live in ~/.config/lostty/config "
                 + "(Lostty → Preferences… opens it).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            sidebar: SidebarPreferences(defaults: UserDefaults(suiteName: "preview")!),
            observer: ObserverPreferences(defaults: UserDefaults(suiteName: "preview")!),
            handoff: ContextHandoffPreferences(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
