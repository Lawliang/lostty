#if os(iOS)
import LosttyRemote
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?

    var body: some View {
        Form {
            Section("Mac") {
                TextField("Address (Tailscale name or IP)", text: $store.settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("User", text: $store.settings.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $store.settings.port, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Lostty terminfo on the Mac", text: $store.settings.terminfoDir)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            }
            if let problem = store.settings.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            Section {
                Button("Show This Phone's Key") {
                    publicKey = (try? store.remoteKey())?.publicKeyLine
                }
                if let publicKey {
                    Text(publicKey).font(.footnote.monospaced()).textSelection(.enabled)
                    ShareLink(item: publicKey)
                }
            } header: {
                Text("Key")
            } footer: {
                Text("Add this line to ~/.ssh/authorized_keys on the Mac.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            Button("Done") {
                store.saveSettings()
                dismiss()
            }
        }
    }
}
#endif
