#if os(macOS)
import CoreImage.CIFilterBuiltins
import LosttyRemote
import SwiftUI

struct PhoneAccessView: View {
    @EnvironmentObject private var store: PhoneAccessStore
    @State private var renaming: PairedPhone?
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                ForEach(store.rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(row.state)).foregroundStyle(color(row.state))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.headline)
                            Text(row.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        ForEach(row.fixes, id: \.self) { fix in
                            Button(label(fix)) { store.fix(fix) }
                        }
                    }
                }
                if store.status == nil || store.checking { ProgressView().controlSize(.small) }
            } header: {
                HStack {
                    Text("This Mac")
                    Spacer()
                    Button("Check Again") { store.refresh() }.disabled(store.checking)
                }
            } footer: {
                Text("Your phone can reach this Mac only while it's awake.").foregroundStyle(.secondary)
            }

            Section {
                Button("Pair a Phone…") { store.startPairing() }.disabled(!store.canPair)
                if let message = store.message { Text(message).foregroundStyle(.secondary) }
            }

            Section("Paired Phones") {
                if store.phones.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(store.phones) { phone in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phone.name)
                            if let paired = phone.paired {
                                Text("Paired \(paired.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Rename…") {
                            newName = phone.name
                            renaming = phone
                        }
                        Button("Remove", role: .destructive) { store.remove(phone) }
                    }
                }
                Button("Turn Off Phone Access…", role: .destructive) { store.turnOff() }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 600)
        .sheet(item: Binding(get: { store.pairing.map(PairingSheetItem.init) }, set: { if $0 == nil { store.stopPairing() } })) { item in
            PairingSheet(pairing: item.pairing).environmentObject(store)
        }
        .alert("Rename Phone", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let phone = renaming { store.rename(phone, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func icon(_ state: PhoneAccessRow.State) -> String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "xmark.circle.fill"
        }
    }

    private func color(_ state: PhoneAccessRow.State) -> Color {
        switch state {
        case .ok: .green
        case .warning: .orange
        case .missing: .red
        }
    }

    private func label(_ fix: PhoneAccessRow.Fix) -> String {
        switch fix {
        case .installTailscale: "Get Tailscale"
        case .openTailscale: "Open Tailscale"
        case .copyBrew: "Copy Command"
        case .adminSetup: "Turn On…"
        case .lockPasswords: "Turn Off Password Logins…"
        case .skipLockdown: "Skip"
        case .openFirewall: "Open Network Settings"
        case .installTerminfo: "Install"
        case .grantFolders: "Grant Now…"
        case .openFilesAndFolders: "Open Privacy Settings"
        }
    }
}

private struct PairingSheetItem: Identifiable {
    var pairing: PhoneAccessStore.Pairing
    // Constant, so a new code or expiry updates the open sheet instead of
    // replacing it (which could dismiss it and stop the new server).
    var id: String { "pairing" }
}

private struct PairingSheet: View {
    @EnvironmentObject private var store: PhoneAccessStore
    var pairing: PhoneAccessStore.Pairing

    var body: some View {
        VStack(spacing: 16) {
            switch pairing {
            case .showing(let payload, let expires):
                Text("Scan this with Lostty on your iPhone.").font(.headline)
                if let image = Self.qrImage(payload.url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 280, height: 280)
                }
                Text("The code works once and expires \(expires, style: .relative).")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Copy Pairing Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payload.url.absoluteString, forType: .string)
                }
            case .expired:
                Text("This code expired.").font(.headline)
                Button("Show a New Code") { store.startPairing() }
            }
            Button("Cancel", role: .cancel) { store.stopPairing() }.keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    static func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
#endif
