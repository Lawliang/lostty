#if os(macOS)
import Foundation
import LosttyRemote

/// One checklist row: what it checks, how it stands, and what can fix it.
struct PhoneAccessRow: Identifiable, Equatable {
    enum Kind: String { case tailscale, tmux, remoteLogin, passwords, firewall, terminfo }
    enum State: Equatable { case ok, warning, missing }
    enum Fix: Equatable { case installTailscale, openTailscale, copyBrew, adminSetup, lockPasswords, skipLockdown, openFirewall, installTerminfo }

    var id: Kind
    var title: String
    var detail: String
    var state: State
    var fixes: [Fix]

    static let skipWarning = "Without this, anyone who can reach this Mac can try your password over SSH, on any network, for every account on this Mac. If you SSH into this Mac with a password from elsewhere, that keeps working."

    static func rows(for s: PhoneAccessStatus, lockdownSkipped: Bool) -> [PhoneAccessRow] {
        var rows: [PhoneAccessRow] = []

        switch s.tailscale {
        case nil:
            rows.append(.init(id: .tailscale, title: "Tailscale", detail: "Install Tailscale and sign in.", state: .missing, fixes: [.installTailscale]))
        case let t? where !t.running:
            rows.append(.init(id: .tailscale, title: "Tailscale", detail: "Open Tailscale and sign in.", state: .missing, fixes: [.openTailscale]))
        case let t? where t.name == nil || t.ipv4 == nil:
            rows.append(.init(id: .tailscale, title: "Tailscale", detail: "Tailscale hasn't given this Mac a name and address yet.", state: .missing, fixes: [.openTailscale]))
        case let t?:
            rows.append(.init(id: .tailscale, title: "Tailscale", detail: t.name ?? "", state: .ok, fixes: []))
        }

        if let path = s.tmuxPath {
            rows.append(.init(id: .tmux, title: "tmux", detail: path, state: .ok, fixes: []))
        } else {
            rows.append(.init(id: .tmux, title: "tmux", detail: "Install it with Homebrew: brew install tmux", state: .missing, fixes: [.copyBrew]))
        }

        rows.append(s.remoteLogin
            ? .init(id: .remoteLogin, title: "Remote Login", detail: "On.", state: .ok, fixes: [])
            : .init(id: .remoteLogin, title: "Remote Login", detail: "Lets your phone sign in to this Mac over SSH.", state: .missing, fixes: [.adminSetup]))

        let passwords: PhoneAccessRow
        if !s.remoteLogin {
            passwords = .init(id: .passwords, title: "Password logins off", detail: "Needs Remote Login.", state: .missing, fixes: [])
        } else if s.passwordsOff {
            passwords = .init(id: .passwords, title: "Password logins off", detail: "Only keys can sign in.", state: .ok, fixes: [])
        } else if s.lockdownFileExists {
            passwords = .init(id: .passwords, title: "Password logins off",
                              detail: "Another SSH setting on this Mac keeps password logins on. Check /etc/ssh/sshd_config and /etc/ssh/sshd_config.d.",
                              state: .missing, fixes: [])
        } else if lockdownSkipped {
            passwords = .init(id: .passwords, title: "Password logins off", detail: skipWarning, state: .warning, fixes: [.lockPasswords])
        } else {
            passwords = .init(id: .passwords, title: "Password logins off",
                              detail: "Anyone who can reach this Mac can try your password over SSH.",
                              state: .missing, fixes: [.lockPasswords, .skipLockdown])
        }
        rows.append(passwords)

        rows.append(s.blockAllIncoming
            ? .init(id: .firewall, title: "Firewall", detail: "The firewall blocks all incoming connections, including your phone.", state: .missing, fixes: [.openFirewall])
            : .init(id: .firewall, title: "Firewall", detail: "Lets your phone in.", state: .ok, fixes: []))

        rows.append(s.terminfoInstalled
            ? .init(id: .terminfo, title: "Terminal definition", detail: "In ~/.terminfo.", state: .ok, fixes: [])
            : .init(id: .terminfo, title: "Terminal definition", detail: "Lets tmux draw Lostty's terminal correctly for your phone.", state: .missing, fixes: [.installTerminfo]))
        return rows
    }
}

/// What the customer (or the keys file) decided for one pairing.
enum PairingDecision: Equatable {
    case allowed, denied, writeFailed

    /// The message once a pairing ends; nil keeps the message already shown
    /// (a write failure already explained itself).
    static func finishedMessage(_ decision: PairingDecision?, allowed: Bool) -> String? {
        switch decision {
        case .writeFailed: nil
        case .denied: "Pairing was declined."
        case .allowed: "Paired. Finish on your phone."
        case nil: allowed ? "Paired. Finish on your phone." : "Pairing didn't finish."
        }
    }
}

struct PairedPhone: Identifiable, Equatable {
    var id: String
    var name: String
    var paired: Date?
}

/// Names and pairing dates of paired phones, by the id in their
/// authorized_keys line.
struct PhoneAccessNames {
    static let defaultsKey = "LosttyPairedPhones"

    struct Entry: Codable, Equatable {
        var name: String
        var paired: Date
    }

    var defaults: UserDefaults

    func entries() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    func set(_ id: String, _ entry: Entry?) {
        var all = entries()
        all[id] = entry
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// The phones in the keys file, named; "iPhone" when no name is stored.
    static func phones(keysText: String, names: [String: Entry]) -> [PairedPhone] {
        AuthorizedKeys.phones(in: keysText).map { phone in
            PairedPhone(id: phone.id, name: names[phone.id]?.name ?? "iPhone", paired: names[phone.id]?.paired)
        }
    }
}

enum PhoneAccessHostKey {
    static let path = "/etc/ssh/ssh_host_ed25519_key.pub"

    /// The base64 field of an ed25519 .pub file; nil for anything else.
    static func base64(fromPub text: String) -> String? {
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0] == "ssh-ed25519" else { return nil }
        return String(fields[1])
    }
}
#endif
