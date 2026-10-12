#if os(macOS)
import AppKit

/// Everything Phone Access does as root, behind one standard macOS admin
/// password prompt. Remote Login is turned on through launchd (what System
/// Settings toggles), never `systemsetup`, which needs Full Disk Access.
/// sshd starts per connection, so changes apply to the next one.
enum PhoneAccessAdmin {
    /// The script for the prompt; nil when there is nothing to do.
    static func setupScript(enableRemoteLogin: Bool, lockPasswords: Bool) -> String? {
        var lines: [String] = []
        if enableRemoteLogin {
            lines.append("launchctl enable system/com.openssh.sshd")
            // Fails when sshd is already loaded; the re-check decides success.
            lines.append("launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true")
        }
        if lockPasswords {
            let path = PhoneAccessProbe.lockdownPath
            lines.append("printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\n' > \(path)")
            lines.append("chmod 644 \(path)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// One script for the prompt. `do shell script` reports only the last
    /// command's status, so the optional stay-awake install goes first and
    /// can't fail the script; the setup lines keep deciding the outcome.
    /// Alone, the install is unwrapped so its failure is reported.
    static func combinedScript(setup: String?, stayAwake: String?) -> String? {
        switch (setup, stayAwake) {
        case let (setup?, stayAwake?): "( \(stayAwake) ) || true\n" + setup
        case let (setup?, nil): setup
        case let (nil, stayAwake?): stayAwake
        case (nil, nil): nil
        }
    }

    /// Turns password logins back on (Turn Off Phone Access).
    /// What the admin prompt says the script does.
    static func prompt(enableRemoteLogin: Bool, lockPasswords: Bool) -> String {
        switch (enableRemoteLogin, lockPasswords) {
        case (true, true): "Lostty wants to turn on Remote Login and turn off SSH password logins for every account on this Mac."
        case (false, true): "Lostty wants to turn off SSH password logins for every account on this Mac."
        default: "Lostty wants to turn on Remote Login for your phone."
        }
    }

    static var unlockScript: String { "rm -f \(PhoneAccessProbe.lockdownPath)" }

    static func appleScript(running script: String, prompt: String) -> String {
        "do shell script \"\(escape(script))\" with prompt \"\(escape(prompt))\" with administrator privileges"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    enum Outcome: Equatable {
        case done
        case cancelled
        case failed(String)
    }

    /// Shows the admin prompt and runs `script` as root. Modal; main thread
    /// only (NSAppleScript isn't thread-safe).
    @MainActor
    static func run(_ script: String, prompt: String) -> Outcome {
        var error: NSDictionary?
        NSAppleScript(source: appleScript(running: script, prompt: prompt))?.executeAndReturnError(&error)
        guard let error else { return .done }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        return .failed(error[NSAppleScript.errorMessage] as? String ?? "The admin step didn't finish.")
    }
}
#endif
