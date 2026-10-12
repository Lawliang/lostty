#if os(iOS)
import LosttyRemote
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?
    @State private var keyError: String?
    @State private var confirmForget = false
    @State private var showPairing = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Mac") {
                if store.settings.paired {
                    LabeledContent("Paired with", value: store.settings.host)
                    if let date = store.settings.pairedAt {
                        LabeledContent("Since", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Button(store.settings.paired ? "Pair with a Different Mac" : "Pair with Mac") { showPairing = true }
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Address (Tailscale name or IP)", text: $store.settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("User", text: $store.settings.user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $store.settings.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    if let problem = store.settings.problem, !store.settings.host.isEmpty {
                        Text(problem).foregroundStyle(.red)
                    }
                    Button("Show This Phone's Key") {
                        do {
                            publicKey = try store.remoteKey().publicKeyLine
                            keyError = nil
                        } catch {
                            publicKey = nil
                            keyError = (error as? RemoteError)?.message ?? error.localizedDescription
                        }
                    }
                    if let keyError { Text(keyError).foregroundStyle(.red) }
                    if let publicKey {
                        Text(publicKey).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: publicKey)
                    }
                    Button("Forget the Mac's Host Key", role: .destructive) { confirmForget = true }
                }
            } footer: {
                Text("For setting up by hand. Pairing fills these in for you.")
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
        .sheet(isPresented: $showPairing) {
            NavigationStack { PairingScreen() }
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
