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

    /// A binding for a field typed by hand: changing it means this is no
    /// longer the paired Mac (a programmatic change by pairing doesn't go
    /// through here).
    private func editedByHand(_ field: WritableKeyPath<RemoteHostSettings, String>) -> Binding<String> {
        Binding(
            get: { store.settings[keyPath: field] },
            set: { new in
                guard new != store.settings[keyPath: field] else { return }
                store.settings[keyPath: field] = new
                store.settings.fallbackHost = nil
                store.settings.pairedAt = nil
            })
    }

    var body: some View {
        Form {
            Section("Mac") {
                if store.settings.paired {
                    LabeledContent("Paired with") {
                        Text(store.settings.host).font(LosttyFont.mono(.callout)).foregroundStyle(LosttyTheme.textSecondary)
                    }
                    if let date = store.settings.pairedAt {
                        LabeledContent("Since", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Button(store.settings.paired ? "Pair with a Different Mac" : "Pair with Mac") { showPairing = true }
            }
            .listRowBackground(LosttyTheme.surface)

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Address (Tailscale name or IP)", text: editedByHand(\.host))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("User", text: editedByHand(\.user))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $store.settings.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    if let problem = store.settings.problem, !store.settings.host.isEmpty {
                        Text(problem).foregroundStyle(LosttyTheme.danger)
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
                    if let keyError { Text(keyError).foregroundStyle(LosttyTheme.danger) }
                    if let publicKey {
                        Text(publicKey).font(LosttyFont.mono(.footnote, size: 13)).textSelection(.enabled)
                        ShareLink(item: publicKey)
                    }
                    Button("Forget the Mac's Host Key", role: .destructive) { confirmForget = true }
                }
            } footer: {
                Text("For setting up by hand. Pairing fills these in for you.")
            }
            .listRowBackground(LosttyTheme.surface)
        }
        .navigationTitle("Settings")
        .losttyScreen()
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
