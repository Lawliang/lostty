#if os(macOS)
import CoreImage.CIFilterBuiltins
import LosttyRemote
import SwiftUI

struct PhoneAccessView: View {
    @EnvironmentObject private var store: PhoneAccessStore
    @State private var renaming: PairedPhone?
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LosttyCard(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                            StatusRow(status: status(row.state), title: row.title, detail: row.detail) {
                                ForEach(row.fixes, id: \.self) { fix in
                                    Button(label(fix)) { store.fix(fix) }.buttonStyle(.lostty(.secondary))
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        if store.status == nil {
                            ProgressView().controlSize(.small).padding(16)
                        }
                    }
                }
                Text("Your phone can reach this Mac only while it's awake. Stay Awake for Phone in the menu bar keeps it awake with the lid closed.")
                    .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                Toggle("Show Lostty in the menu bar", isOn: Binding(
                    get: { LosttyStatusItem.isEnabled },
                    set: { LosttyStatusItem.isEnabled = $0 }))
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textPrimary)

                Button("Pair a Phone…") { store.startPairing() }
                    .buttonStyle(.lostty(.primary, fullWidth: true))
                    .disabled(!store.canPair)
                if let message = store.message {
                    Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                }

                Text("Paired phones").font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                LosttyCard(padding: 4) {
                    VStack(spacing: 0) {
                        if store.phones.isEmpty {
                            Text("None yet.").font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(store.phones.enumerated()), id: \.element.id) { index, phone in
                            if index > 0 { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                            HStack(spacing: 12) {
                                Image(systemName: "iphone").foregroundStyle(LosttyTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phone.name).font(LosttyFont.bodyEmphasis).foregroundStyle(LosttyTheme.textPrimary)
                                    if let paired = phone.paired {
                                        Text("Paired \(paired.formatted(date: .abbreviated, time: .omitted))")
                                            .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                Button("Rename…") {
                                    newName = phone.name
                                    renaming = phone
                                }
                                .buttonStyle(.lostty(.quiet))
                                Button("Remove") { store.remove(phone) }.buttonStyle(.lostty(.quietDanger))
                            }
                            .padding(12)
                        }
                    }
                }
                Button("Turn Off Phone Access…") { store.turnOff() }
                    .buttonStyle(.lostty(.quietDanger))
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(minHeight: 520)
        .background(LosttyTheme.background)
        .sheet(item: Binding(get: { store.pairing.map(PairingSheetItem.init) }, set: { if $0 == nil { store.stopPairing() } })) { item in
            PairingSheet(pairing: item.pairing).environmentObject(store)
        }
        .alert("Rename Phone", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let phone = renaming { store.rename(phone, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Axolotl(pose: .resting).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone Access").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                let readiness = PhoneAccessRow.readiness(store.rows)
                if readiness.total > 0 {
                    Text("\(readiness.ready) of \(readiness.total) ready")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                }
            }
            Spacer()
            if store.checking { ProgressView().controlSize(.small) }
            Button("Check Again") { store.refresh() }.buttonStyle(.lostty(.quiet)).disabled(store.checking)
        }
    }

    private func status(_ state: PhoneAccessRow.State) -> StatusRowStatus {
        switch state {
        case .ok: .ok
        case .warning: .warning
        case .missing: .missing
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
        case .installStayAwake: "Install…"
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
        ZStack {
            BlueprintBackground()
            VStack(spacing: 18) {
                switch pairing {
                case .showing(let payload, let expires):
                    Axolotl(pose: .waiting).frame(width: 56, height: 56)
                    Text("Scan this with Lostty on your iPhone.")
                        .font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        qrTile(payload, fraction: PairingCountdown.fraction(now: context.date, expires: expires))
                    }
                    Text("The code works once and expires \(expires, style: .relative).")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    Button("Copy Pairing Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload.url.absoluteString, forType: .string)
                    }
                    .buttonStyle(.lostty(.secondary))
                case .expired:
                    Axolotl(pose: .resting).frame(width: 56, height: 56)
                    Text("This code expired.").font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                    Button("Show a New Code") { store.startPairing() }.buttonStyle(.lostty(.primary))
                }
                Button("Cancel", role: .cancel) { store.stopPairing() }
                    .buttonStyle(.lostty(.quiet))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
        }
        .frame(width: 380)
    }

    /// The QR on white (cameras read dark-on-light best), with a magenta ring
    /// that empties as the code's two minutes run out.
    private func qrTile(_ payload: PairingPayload, fraction: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LosttyTheme.radius + 8, style: .continuous)
                .stroke(LosttyTheme.hairline, lineWidth: 4)
            RoundedRectangle(cornerRadius: LosttyTheme.radius + 8, style: .continuous)
                .trim(from: 0, to: fraction)
                .stroke(LosttyTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .animation(LosttyTheme.motion, value: fraction)
            if let image = Self.qrImage(payload.url.absoluteString) {
                Image(nsImage: image).interpolation(.none).resizable()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
                    .padding(12)
                    .accessibilityLabel("Pairing code")
            }
        }
        .frame(width: 280, height: 280)
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
