#if os(macOS)
import AppKit
import LosttyRemote

/// The Phone Access window's state: the checklist, its fixes, pairing, and
/// the paired phones.
@MainActor
final class PhoneAccessStore: ObservableObject {
    enum Pairing: Equatable {
        case showing(PairingPayload, expires: Date)
        case expired
    }

    @Published private(set) var status: PhoneAccessStatus?
    @Published private(set) var checking = false
    @Published private(set) var phones: [PairedPhone] = []
    @Published var pairing: Pairing?
    @Published var message: String?

    static let skipDefaultsKey = "LosttyPhoneAccessSkipLockdown"
    private let defaults = UserDefaults.ghostty
    private var server: PairingServer?
    private var pairingID = UUID()
    private var decision: PairingDecision?
    private let keysFile = AuthorizedKeysFile.standard
    private var names: PhoneAccessNames { PhoneAccessNames(defaults: defaults) }

    var lockdownSkipped: Bool {
        get { defaults.bool(forKey: Self.skipDefaultsKey) }
        set {
            defaults.set(newValue, forKey: Self.skipDefaultsKey)
            objectWillChange.send()
        }
    }

    var rows: [PhoneAccessRow] {
        status.map { PhoneAccessRow.rows(for: $0, lockdownSkipped: lockdownSkipped) } ?? []
    }

    var canPair: Bool { status?.readyToPair(lockdownSkipped: lockdownSkipped) == true }

    func refresh() {
        checking = true
        Task.detached(priority: .userInitiated) {
            let status = PhoneAccessProbe.run()
            await MainActor.run {
                self.status = status
                self.checking = false
            }
        }
        reloadPhones()
    }

    func reloadPhones() {
        phones = PhoneAccessNames.phones(keysText: (try? keysFile.read()) ?? "", names: names.entries())
    }

    // MARK: Fixes

    func fix(_ fix: PhoneAccessRow.Fix) {
        switch fix {
        case .installTailscale:
            NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!)
        case .openTailscale:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
        case .copyBrew:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install tmux", forType: .string)
            message = "Copied “brew install tmux”. Run it in a terminal, then come back. No Homebrew? See brew.sh."
        case .adminSetup:
            runAdmin(enableRemoteLogin: true, lockPasswords: !lockdownSkipped && status?.passwordsOff != true)
        case .lockPasswords:
            lockdownSkipped = false
            runAdmin(enableRemoteLogin: status?.remoteLogin != true, lockPasswords: true)
        case .skipLockdown:
            let alert = NSAlert()
            alert.messageText = "Keep password logins on?"
            alert.informativeText = PhoneAccessRow.skipWarning
            alert.addButton(withTitle: "Keep Them On")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { lockdownSkipped = true }
        case .openFirewall:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
        case .installTerminfo:
            do {
                try PhoneAccessTerminfo.install(bundle: PhoneAccessTerminfo.bundleDirectory, home: PhoneAccessTerminfo.homeDirectory)
            } catch {
                message = "Couldn't copy the terminal definition: \(error.localizedDescription)"
            }
            refresh()
        }
    }

    private func runAdmin(enableRemoteLogin: Bool, lockPasswords: Bool) {
        guard let script = PhoneAccessAdmin.setupScript(enableRemoteLogin: enableRemoteLogin, lockPasswords: lockPasswords) else {
            refresh()
            return
        }
        switch PhoneAccessAdmin.run(script, prompt: "Lostty wants to set up Remote Login for your phone.") {
        case .done, .cancelled: break
        case .failed(let text): message = text
        }
        refresh()
    }

    // MARK: Pairing

    func startPairing() {
        guard let tailscale = status?.tailscale, let name = tailscale.name, let ip = tailscale.ipv4 else { return }
        do {
            let pub = try String(contentsOfFile: PhoneAccessHostKey.path, encoding: .utf8)
            guard let hostKey = PhoneAccessHostKey.base64(fromPub: pub) else { throw PairingError.invalidLink }
            let payload = try PairingPayload(name: name, ip: ip, user: NSUserName(), hostKey: hostKey, secret: PairingPayload.newSecret())
            let id = UUID()
            let server = try PairingServer(
                secret: payload.secret,
                decide: { [weak self] request in await self?.ask(request, pairing: id) ?? false },
                onFinish: { [weak self] allowed in
                    Task { @MainActor in self?.pairingFinished(id, allowed: allowed) }
                })
            stopPairing()
            self.server = server
            pairingID = id
            decision = nil
            pairing = .showing(payload, expires: Date().addingTimeInterval(120))
            Task {
                do {
                    _ = try await server.start()
                } catch {
                    if pairingID == id {
                        message = "Couldn't start pairing. Check that Lostty may use the local network (System Settings → Privacy & Security → Local Network)."
                        stopPairing()
                    }
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(120))
                if pairingID == id, case .showing = pairing {
                    server.stop()
                    self.server = nil
                    pairingID = UUID()
                    pairing = .expired
                }
            }
        } catch {
            message = "This Mac has no SSH host key yet. Make sure Remote Login is on, then try again."
        }
    }

    func stopPairing() {
        server?.stop()
        server = nil
        pairingID = UUID()
        pairing = nil
    }

    /// The Allow prompt; on Allow, adds the key.
    private func ask(_ request: PairingRequest, pairing id: UUID) async -> Bool {
        guard pairingID == id, let key = request.acceptedKey else { return false }
        let model = request.displayModel
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow “\(model)” to open your Lostty sessions?"
        alert.informativeText = "It can open and type in every Lostty session on this Mac. You can remove it later in Phone Access."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        let allowed = alert.runModal() == .alertFirstButtonReturn
        // Cancel or expiry can happen while the alert is up.
        guard pairingID == id else { return false }
        guard allowed else {
            decision = .denied
            return false
        }
        do {
            let id = UUID().uuidString.lowercased()
            let text = try keysFile.read()
            if let updated = AuthorizedKeys.adding(key: key, id: id, to: text) {
                try keysFile.write(updated)
                names.set(id, .init(name: model, paired: Date()))
            }
            decision = .allowed
            return true
        } catch {
            decision = .writeFailed
            message = "Couldn't add the phone to ~/.ssh/authorized_keys: \(error.localizedDescription)"
            return false
        }
    }

    private func pairingFinished(_ id: UUID, allowed: Bool) {
        guard pairingID == id else { return }
        server = nil
        pairing = nil
        if let text = PairingDecision.finishedMessage(decision, allowed: allowed) { message = text }
        reloadPhones()
    }

    // MARK: Paired phones

    func rename(_ phone: PairedPhone, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        names.set(phone.id, .init(name: trimmed, paired: phone.paired ?? Date()))
        reloadPhones()
    }

    func remove(_ phone: PairedPhone) {
        do {
            try keysFile.write(AuthorizedKeys.removing(id: phone.id, from: try keysFile.read()))
            names.set(phone.id, nil)
        } catch {
            message = "Couldn't update ~/.ssh/authorized_keys: \(error.localizedDescription)"
        }
        reloadPhones()
    }

    /// Removes every paired phone, then offers to turn password logins back
    /// on. Remote Login is left as it is.
    func turnOff() {
        let confirm = NSAlert()
        confirm.messageText = "Turn off Phone Access?"
        confirm.informativeText = "Every paired phone is removed from ~/.ssh/authorized_keys and can't open your sessions anymore."
        confirm.addButton(withTitle: "Turn Off")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        stopPairing()
        do {
            try keysFile.write(AuthorizedKeys.removingAll(from: try keysFile.read()))
            for phone in phones { names.set(phone.id, nil) }
        } catch {
            message = "Couldn't update ~/.ssh/authorized_keys: \(error.localizedDescription)"
        }
        if FileManager.default.fileExists(atPath: PhoneAccessProbe.lockdownPath) {
            let unlock = NSAlert()
            unlock.messageText = "Turn password logins back on?"
            unlock.informativeText = "Lostty turned them off for Phone Access. Keeping them off is safer."
            unlock.addButton(withTitle: "Keep Them Off")
            unlock.addButton(withTitle: "Turn Back On")
            if unlock.runModal() == .alertSecondButtonReturn,
               case .failed(let text) = PhoneAccessAdmin.run(PhoneAccessAdmin.unlockScript, prompt: "Lostty wants to turn password logins back on.") {
                message = text
            }
        }
        lockdownSkipped = false
        refresh()
    }
}
#endif
