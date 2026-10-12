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

    static let stayAwakePrompt = "Lostty wants to keep this Mac awake for your phone when you ask it to."
    static let skipDefaultsKey = "LosttyPhoneAccessSkipLockdown"
    private let defaults = UserDefaults.ghostty
    private var server: PairingServer?
    private var pairingID = UUID()
    private var decision: PairingDecision?
    private let keysFile = AuthorizedKeysFile.standard
    private var names: PhoneAccessNames { PhoneAccessNames(defaults: defaults) }

    var lockdownSkipped: Bool {
        get {
            #if DEBUG
            if let galleryLockdownSkipped { return galleryLockdownSkipped }
            #endif
            return defaults.bool(forKey: Self.skipDefaultsKey)
        }
        set {
            defaults.set(newValue, forKey: Self.skipDefaultsKey)
            objectWillChange.send()
        }
    }

    #if DEBUG
    /// Design Gallery only: a window frozen in one state.
    static func gallery(
        status: PhoneAccessStatus, lockdownSkipped: Bool = false, phones: [PairedPhone] = [],
        pairing: Pairing? = nil, message: String? = nil
    ) -> PhoneAccessStore {
        let store = PhoneAccessStore()
        store.status = status
        store.phones = phones
        store.pairing = pairing
        store.message = message
        store.galleryLockdownSkipped = lockdownSkipped
        return store
    }
    private var galleryLockdownSkipped: Bool?
    #endif

    var rows: [PhoneAccessRow] {
        status.map { PhoneAccessRow.rows(for: $0, lockdownSkipped: lockdownSkipped) } ?? []
    }

    var canPair: Bool { status?.readyToPair(lockdownSkipped: lockdownSkipped) == true }

    func refresh() {
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
        checking = true
        let requested = defaults.bool(forKey: PhoneAccessFolders.requestedDefaultsKey)
        Task.detached(priority: .userInitiated) {
            let status = PhoneAccessProbe.run(foldersRequested: requested)
            await MainActor.run {
                self.status = status
                self.checking = false
            }
        }
        reloadPhones()
    }

    func reloadPhones() {
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
        phones = PhoneAccessNames.phones(keysText: (try? keysFile.read()) ?? "", names: names.entries())
    }

    // MARK: Fixes

    func fix(_ fix: PhoneAccessRow.Fix) {
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
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
        case .installStayAwake:
            guard let script = StayAwakeSudoers.installScript(user: NSUserName()) else {
                message = "Stay Awake for Phone can't be set up for this account name."
                return
            }
            if case .failed(let text) = PhoneAccessAdmin.run(script, prompt: Self.stayAwakePrompt) {
                message = text
            }
            StayAwakeStore.shared.refreshAvailability()
            refresh()
        case .grantFolders:
            // macOS asks once per folder and the read waits for each answer.
            checking = true
            Task.detached(priority: .userInitiated) {
                _ = PhoneAccessFolders.check()
                await MainActor.run {
                    self.defaults.set(true, forKey: PhoneAccessFolders.requestedDefaultsKey)
                    self.refresh()
                }
            }
        case .openFilesAndFolders:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
        }
    }

    private func runAdmin(enableRemoteLogin: Bool, lockPasswords: Bool) {
        let setup = PhoneAccessAdmin.setupScript(enableRemoteLogin: enableRemoteLogin, lockPasswords: lockPasswords)
        let stayAwake = status?.stayAwakePermission == false ? StayAwakeSudoers.installScript(user: NSUserName()) : nil
        let script = [setup, stayAwake].compactMap { $0 }.joined(separator: "\n")
        guard !script.isEmpty else {
            refresh()
            return
        }
        var prompt = setup == nil
            ? Self.stayAwakePrompt
            : PhoneAccessAdmin.prompt(enableRemoteLogin: enableRemoteLogin, lockPasswords: lockPasswords)
        if setup != nil && stayAwake != nil { prompt += " It also lets Lostty keep this Mac awake for your phone when you ask." }
        switch PhoneAccessAdmin.run(script, prompt: prompt) {
        case .done, .cancelled: break
        case .failed(let text): message = text
        }
        StayAwakeStore.shared.refreshAvailability()
        refresh()
    }

    // MARK: Pairing

    func startPairing() {
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
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
            let text = try keysFile.read()
            switch AuthorizedKeys.status(of: key, in: text) {
            case .lostty:
                // Already paired: keep its line and name.
                break
            case .absent:
                let newID = UUID().uuidString.lowercased()
                try keysFile.write(AuthorizedKeys.adding(key: key, id: newID, to: text) ?? text)
                names.set(newID, .init(name: model, paired: Date()))
            case .foreign:
                let replace = NSAlert()
                replace.messageText = "This phone's key is already in ~/.ssh/authorized_keys on a line Lostty didn't add. Replace it with a Phone Access line?"
                replace.addButton(withTitle: "Replace")
                replace.addButton(withTitle: "Cancel")
                let replaced = replace.runModal() == .alertFirstButtonReturn
                guard pairingID == id else { return false }
                guard replaced else {
                    decision = .denied
                    return false
                }
                let newID = UUID().uuidString.lowercased()
                try keysFile.write(AuthorizedKeys.replacingForeign(key: key, id: newID, in: try keysFile.read()))
                names.set(newID, .init(name: model, paired: Date()))
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
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        names.set(phone.id, .init(name: trimmed, paired: phone.paired ?? Date()))
        reloadPhones()
    }

    func remove(_ phone: PairedPhone) {
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
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
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
        let confirm = NSAlert()
        confirm.messageText = "Turn off Phone Access?"
        confirm.informativeText = "Every paired phone is removed from ~/.ssh/authorized_keys and can't open your sessions anymore."
        confirm.addButton(withTitle: "Turn Off")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        stopPairing()
        StayAwakeStore.shared.turnOff()
        do {
            try keysFile.write(AuthorizedKeys.removingAll(from: try keysFile.read()))
            for phone in phones { names.set(phone.id, nil) }
        } catch {
            message = "Couldn't update ~/.ssh/authorized_keys: \(error.localizedDescription)"
        }
        var adminScripts: [String] = []
        var prompts: [String] = []
        if FileManager.default.fileExists(atPath: StayAwakeSudoers.path) {
            adminScripts.append(StayAwakeSudoers.removeScript)
            prompts.append("remove its permission to keep this Mac awake")
        }
        if FileManager.default.fileExists(atPath: PhoneAccessProbe.lockdownPath) {
            let unlock = NSAlert()
            unlock.messageText = "Turn password logins back on?"
            unlock.informativeText = "Lostty turned them off for Phone Access. Keeping them off is safer."
            unlock.addButton(withTitle: "Keep Them Off")
            unlock.addButton(withTitle: "Turn Back On")
            if unlock.runModal() == .alertSecondButtonReturn {
                adminScripts.append(PhoneAccessAdmin.unlockScript)
                prompts.append("turn password logins back on")
            }
        }
        if !adminScripts.isEmpty,
           case .failed(let text) = PhoneAccessAdmin.run(adminScripts.joined(separator: "\n"),
                                                         prompt: "Lostty wants to " + prompts.joined(separator: " and ") + ".") {
            message = text
        }
        StayAwakeStore.shared.refreshAvailability()
        lockdownSkipped = false
        refresh()
    }
}
#endif
