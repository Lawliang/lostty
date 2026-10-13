#if os(macOS)
import SwiftUI

/// Lostty Settings: preferences that live in the app rather than the
/// config file.
struct SettingsView: View {
    @ObservedObject var sidebar: SidebarPreferences

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
        SettingsView(sidebar: SidebarPreferences(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
