#if os(iOS)
import LosttyRemote
import SwiftUI

/// Whether this phone is paired, with the axolotl as pairing's last step
/// shows it, and the one thing to do about it: unpair, or pair.
struct SettingsScreen: View {
    /// A tab of its own, not a sheet: nothing to dismiss.
    var inTab = false
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPairing = false
    @State private var confirmUnpair = false
    #if DEBUG
    @State private var showManualSetup = false
    #endif

    /// In the middle of the screen, as pairing's "Paired." is; at least
    /// the screen's height, and scrolling once large text makes it taller.
    private var hero: some View {
        VStack(spacing: 20) {
            if store.settings.paired {
                Axolotl(pose: .happy).frame(width: 140, height: 140).losttyGlow(diameter: 330)
                VStack(spacing: 8) {
                    Text("Paired.").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                    Text("This iPhone can open your Mac's sessions.")
                        .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                }
                Button("Unpair") { confirmUnpair = true }
                    .buttonStyle(.lostty(.quietDanger))
            } else {
                Axolotl(pose: .resting).frame(width: 140, height: 140).losttyGlow(diameter: 330)
                VStack(spacing: 8) {
                    Text("Not paired").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                    Text("Pair with your Mac to open its sessions here.")
                        .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                }
                Button("Pair with Mac") { showPairing = true }
                    .buttonStyle(.lostty(.primary, fullWidth: true))
            }
        }
        .multilineTextAlignment(.center)
        // Full width, so a glow wider than the text isn't cut off at
        // the text's edges.
        .frame(maxWidth: .infinity)
        .padding(LosttyTheme.margin)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                hero.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if store.settings.paired { NotificationsRow() }
                TerminalFontRow()
                TerminalTextSizeRow()
            }
            .padding(.horizontal, LosttyTheme.margin)
            .padding(.bottom, 12)
        }
        #if DEBUG
        // Setting up by hand: Debug builds only (the simulator can't
        // pair). Pairing fills all of this in, and pins the Mac's host
        // key, so release builds never need it.
        .safeAreaInset(edge: .bottom) {
            Button("Set Up by Hand") { showManualSetup = true }
                .buttonStyle(.lostty(.quiet))
                .padding(LosttyTheme.margin)
        }
        .sheet(isPresented: $showManualSetup) {
            NavigationStack { ManualSetupScreen() }
        }
        #endif
        .navigationTitle("Settings")
        // In the top bar, as the Terminals tab's title is, so the two
        // tabs' titles sit at the same height.
        .toolbarTitleDisplayMode(.inlineLarge)
        .losttyScreen()
        .animation(LosttyTheme.motion, value: store.settings.paired)
        .confirmationDialog("Unpair from your Mac?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { store.unpair() }
        } message: {
            Text("Your sessions keep running on the Mac. To use them from this phone again, pair from Phone Access on the Mac.")
        }
        .sheet(isPresented: $showPairing) {
            NavigationStack { PairingScreen() }
        }
        .onDisappear { store.saveSettings() }
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .largeTitle) {
                    Text("Settings")
                        .font(LosttyFont.largeTitle)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !inTab {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Every terminal's text size: a step smaller or larger than the default.
/// An open terminal picks it up when shown again.
private struct TerminalTextSizeRow: View {
    @AppStorage(TerminalTextSize.key) private var textSize: TerminalTextSize = .standard

    var body: some View {
        LosttyCard(padding: 0) {
            HStack {
                Text("Terminal Text Size")
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textPrimary)
                Spacer()
                Picker("Terminal Text Size", selection: $textSize) {
                    ForEach(TerminalTextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(LosttyTheme.textSecondary)
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
        }
    }
}

/// Every terminal's font. An open terminal picks it up when shown again.
private struct TerminalFontRow: View {
    @AppStorage(TerminalFontChoice.key) private var font: TerminalFontChoice = .standard

    var body: some View {
        LosttyCard(padding: 0) {
            HStack {
                Text("Terminal Font")
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textPrimary)
                Spacer()
                Picker("Terminal Font", selection: $font) {
                    ForEach(TerminalFontChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(LosttyTheme.textSecondary)
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
        }
    }
}

/// Opens Settings → Notifications.
private struct NotificationsRow: View {
    var body: some View {
        NavigationLink { NotificationSettingsScreen() } label: {
            LosttyCard(padding: 0) {
                HStack {
                    Text("Notifications")
                        .font(LosttyFont.body)
                        .foregroundStyle(LosttyTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LosttyTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// The Mac's address and user typed by hand, and this phone's key to add
/// to the Mac's authorized_keys: for the simulator, which can't pair.
private struct ManualSetupScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?
    @State private var keyError: String?

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
            Section {
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
            }
            .listRowBackground(LosttyTheme.surface)
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
                if let keyError { Text(keyError).foregroundStyle(LosttyTheme.danger) }
                if let publicKey {
                    Text(publicKey).font(LosttyFont.mono(.footnote, size: 13)).textSelection(.enabled)
                    ShareLink(item: publicKey)
                }
            }
            .listRowBackground(LosttyTheme.surface)
        }
        .navigationTitle("Set Up by Hand")
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .onDisappear { store.saveSettings() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    store.saveSettings()
                    dismiss()
                }
            }
        }
    }
}
#endif
#endif
