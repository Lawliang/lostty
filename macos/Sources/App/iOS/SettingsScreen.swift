#if os(iOS)
import LosttyRemote
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?
    @State private var keyError: String?
    @State private var confirmForget = false

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
            }
            if let problem = store.settings.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            Section {
                Button("Show This Phone's Key") {
                    do {
                        publicKey = try store.remoteKey().publicKeyLine
                        keyError = nil
                    } catch {
                        publicKey = nil
                        keyError = (error as? RemoteError)?.message ?? error.localizedDescription
                    }
                }
                if let keyError {
                    Text(keyError).foregroundStyle(.red)
                }
                if let publicKey {
                    Text(publicKey).font(.footnote.monospaced()).textSelection(.enabled)
                    ShareLink(item: publicKey)
                }
                Button("Forget the Mac's Host Key", role: .destructive) { confirmForget = true }
            } header: {
                Text("Key")
            } footer: {
                Text("Add this line to ~/.ssh/authorized_keys on the Mac.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Forget the Mac's host key?", isPresented: $confirmForget, titleVisibility: .visible
        ) {
            Button("Forget Host Key", role: .destructive) { store.forgetHostKey() }
        } message: {
            Text("Only do this if the Mac's SSH host key really changed. The next connection trusts whatever key the address offers.")
        }
        .onDisappear { store.saveSettings() }
        .toolbar {
            Button("Done") {
                store.saveSettings()
                dismiss()
            }
        }
    }
}
#endif
