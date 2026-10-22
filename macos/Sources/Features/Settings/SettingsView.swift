#if os(macOS)
import SwiftUI

/// Lostty Settings: preferences that live in the app rather than the
/// config file.
struct SettingsView: View {
    @ObservedObject var observer: ObserverPreferences
    @ObservedObject var handoff: ContextHandoffPreferences
    @ObservedObject var font: TerminalFontPreferences
    @ObservedObject var updates: UpdatePreferences
    /// A build made on this Mac updates with install.sh, not the updater.
    var hasUpdateFeed = UpdateFeed.current != nil
    /// Turn summaries, while the observer is on.
    var observesTurns = LosttyChannel.current.observesTurns
    /// The Handoff section is for the beta, the only build with the handoff.
    var handsOff = LosttyChannel.current.handsOff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TerminalFontSection(font: font)
                if observesTurns {
                    Section("Turn summaries") {
                        Toggle("Summarize turns in the background", isOn: $observer.background)
                        Text("After each turn, Claude Haiku (or Codex, or Apple Intelligence) updates the "
                             + "turn's summary, using your own subscription. Off, it summarizes only when asked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if handsOff {
                    Section("Handoff") {
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
                Section("Updates") {
                    Toggle("Install updates automatically", isOn: $updates.installsAutomatically)
                        .disabled(!hasUpdateFeed)
                    Text(hasUpdateFeed
                         ? "Lostty downloads each update in the background and offers Restart to Update, "
                            + "which keeps your terminals open. Off, it asks before downloading. "
                            + "auto-update in the config file, when set, wins."
                         : UpdateFeed.localBuildMessage)
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

/// Font, size and line spacing for every terminal, and so for Claude Code
/// and the other agents that run in one.
private struct TerminalFontSection: View {
    @ObservedObject var font: TerminalFontPreferences
    @State private var installed: [String] = []

    private static let spacings: [(label: String, value: String?)] = [
        ("Normal", nil), ("+10%", "10%"), ("+20%", "20%"), ("+30%", "30%"),
    ]

    var body: some View {
        Section("Terminal font") {
            Picker("Font", selection: binding(\.family)) {
                Text("\(TerminalFontSettings.defaultFamily) (built in)").tag(String?.none)
                if !readable.isEmpty {
                    Divider()
                    ForEach(readable, id: \.self) { family in
                        let included = BundledTerminalFonts.families.contains(family)
                        Text(included ? "\(family) (included)" : family).tag(String?.some(family))
                    }
                }
                if !others.isEmpty {
                    Divider()
                    ForEach(others, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            Stepper(value: sizeBinding, in: 9...32, step: 1) {
                LabeledContent("Size", value: "\(Int(font.settings.size ?? TerminalFontSettings.defaultSize)) pt")
            }
            Picker("Line spacing", selection: binding(\.cellHeight)) {
                ForEach(spacings, id: \.label) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            Text("Applies to every open terminal right away, including Claude Code. "
                 + "Larger sizes and a little extra line spacing help most.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = font.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            installed = TerminalFontCatalog.installedFamilies()
        }
    }

    /// The suggested families that are installed, then everything else.
    /// A family set by hand that isn't installed still shows, so the picker
    /// never loses the current choice.
    private var readable: [String] {
        TerminalFontCatalog.readable.filter(installed.contains)
    }

    private var others: [String] {
        var rest = installed.filter { !TerminalFontCatalog.readable.contains($0) }
        if let family = font.settings.family, !installed.contains(family) { rest.insert(family, at: 0) }
        return rest
    }

    private var spacings: [(label: String, value: String?)] {
        guard let custom = font.settings.cellHeight,
              !Self.spacings.contains(where: { $0.value == custom }) else { return Self.spacings }
        return Self.spacings + [(custom, custom)]
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { font.settings.size ?? TerminalFontSettings.defaultSize },
            set: { size in
                var settings = font.settings
                settings.size = size == TerminalFontSettings.defaultSize ? nil : size
                font.set(settings)
            })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TerminalFontSettings, Value>) -> Binding<Value> {
        Binding(
            get: { font.settings[keyPath: keyPath] },
            set: { value in
                var settings = font.settings
                settings[keyPath: keyPath] = value
                font.set(settings)
            })
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            observer: ObserverPreferences(defaults: UserDefaults(suiteName: "preview")!),
            handoff: ContextHandoffPreferences(defaults: UserDefaults(suiteName: "preview")!),
            font: TerminalFontPreferences(configURL: { nil }, reloadConfig: {}),
            updates: UpdatePreferences(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
