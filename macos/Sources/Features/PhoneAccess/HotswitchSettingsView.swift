#if os(macOS)
import AppKit
import LosttyRemote
import SwiftUI

/// Phone Access: "Switch to iPhone hotspot when Wi-Fi drops" (Hotswitch),
/// with the three things it needs: which hotspot, its password, Location.
struct HotswitchSettingsView: View {
    @EnvironmentObject private var store: PhoneAccessStore
    @ObservedObject private var hotswitch = Hotswitch.shared
    @State private var networks: [String] = []
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Switch to iPhone hotspot when Wi-Fi drops", isOn: $hotswitch.enabled)
                .font(LosttyFont.body).foregroundStyle(LosttyTheme.textPrimary)
                .disabled(!hotswitch.ready)
            LosttyCard(padding: 4) {
                VStack(spacing: 0) {
                    StatusRow(
                        status: hotswitch.hotspot.isEmpty ? .missing : .ok, title: "Your iPhone's hotspot",
                        detail: "On the iPhone, keep Personal Hotspot → Allow Others to Join on, or this Mac can't find it."
                    ) {
                        Picker("", selection: $hotswitch.hotspot) {
                            if hotswitch.hotspot.isEmpty { Text("Choose…").tag("") }
                            ForEach(choices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 150)
                    }
                    .padding(.horizontal, 12)
                    Rectangle().fill(LosttyTheme.hairline).frame(height: 1)
                    StatusRow(
                        status: hotswitch.hasPassword ? .ok : .missing, title: "Hotspot password",
                        detail: hotswitch.hasPassword
                            ? "Saved in your keychain."
                            : "On the iPhone: Settings → Personal Hotspot → Wi-Fi Password."
                    ) {
                        SecureField(hotswitch.hasPassword ? "Change" : "Password", text: $password)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .onSubmit(save)
                        Button("Save", action: save).buttonStyle(.lostty(.secondary))
                            .disabled(password.isEmpty || hotswitch.hotspot.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    Rectangle().fill(LosttyTheme.hairline).frame(height: 1)
                    StatusRow(
                        status: hotswitch.locationAllowed ? .ok : .missing, title: "Location",
                        detail: "macOS shows Wi-Fi network names only to apps with Location."
                    ) {
                        if !hotswitch.locationAllowed {
                            if hotswitch.location == .notDetermined {
                                Button("Allow…") { hotswitch.askForLocation() }.buttonStyle(.lostty(.secondary))
                            } else {
                                Button("Open Settings") { openLocationSettings() }.buttonStyle(.lostty(.secondary))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            Text(statusLine)
                .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
        }
        .onAppear(perform: load)
    }

    private var choices: [String] {
        networks.contains(hotswitch.hotspot) || hotswitch.hotspot.isEmpty ? networks : [hotswitch.hotspot] + networks
    }

    private var statusLine: String {
        if !hotswitch.ready { return "Needs all three above. Works only while Stay Awake for Phone is on." }
        return HotswitchMenuText.status(hotswitch.status)
            ?? "While Stay Awake for Phone is on, this Mac moves to your hotspot when Wi-Fi drops, and back when it returns."
    }

    private func load() {
        networks = hotswitch.knownNetworks()
        // First time: the network named like a paired phone ("Law" for "Law's iPhone").
        if hotswitch.hotspot.isEmpty {
            let phones = store.phones.map { $0.name.lowercased() }
            if let match = networks.first(where: { name in phones.contains { $0.hasPrefix(name.lowercased()) } }) {
                hotswitch.hotspot = match
            }
        }
    }

    private func save() {
        hotswitch.savePassword(password)
        password = ""
    }

    private func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum HotswitchMenuText {
    /// "On iPhone hotspot since 9:41 PM", or why it couldn't move.
    static func status(_ status: HotswitchModel.Status?) -> String? {
        switch status {
        case .onHotspot(let since)?: "On iPhone hotspot since \(since.formatted(date: .omitted, time: .shortened))"
        case .failed(let at)?: "Couldn't reach iPhone hotspot · \(at.formatted(date: .omitted, time: .shortened))"
        case nil: nil
        }
    }
}
#endif
