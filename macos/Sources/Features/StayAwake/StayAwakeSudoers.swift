#if os(macOS)
import Foundation

/// The one-time permission: a sudoers rule letting this user run exactly the
/// `PowerCommand`s as root without a password.
enum StayAwakeSudoers {
    static let path = "/etc/sudoers.d/lostty"

    /// nil for a name that isn't a plain account name: anything else could
    /// change what the rule means.
    static func rule(user: String) -> String? {
        guard user.range(of: #"\A[A-Za-z0-9_][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
              user != "ALL"
        else { return nil }
        let commands = PowerCommand.all.map { (["/usr/bin/pmset"] + $0.pmsetArguments).joined(separator: " ") }
        return "\(user) ALL=(root) NOPASSWD: " + commands.joined(separator: ", ")
    }

    /// Runs as root in the admin prompt. visudo checks the file before it is
    /// installed, so a bad rule can never break sudo. Its last command's
    /// status is the script's.
    static func installScript(user: String) -> String? {
        guard let rule = rule(user: user) else { return nil }
        return """
        tmp=$(/usr/bin/mktemp /tmp/lostty-sudoers.XXXXXX) && /usr/bin/printf '%s\\n' '# Lostty: Stay Awake for Phone. Phone Access, Turn Off removes it.' '\(rule)' > "$tmp" && /usr/sbin/visudo -cf "$tmp" >/dev/null && /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(path); rc=$?; /bin/rm -f "$tmp"; [ $rc -eq 0 ]
        """
    }

    static var removeScript: String { "rm -f \(path)" }
}
#endif
