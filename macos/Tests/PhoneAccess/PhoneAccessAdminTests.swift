#if os(macOS)
import Testing
@testable import Ghostty

struct PhoneAccessAdminTests {
    @Test func turnsOnRemoteLoginWithLaunchctlNeverSystemsetup() throws {
        let script = try #require(PhoneAccessAdmin.setupScript(enableRemoteLogin: true, lockPasswords: false))
        #expect(script == """
        launchctl enable system/com.openssh.sshd
        launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
        """)
        #expect(!script.contains("systemsetup"))
    }

    @Test func locksPasswordsWithTheDropIn() throws {
        let script = try #require(PhoneAccessAdmin.setupScript(enableRemoteLogin: false, lockPasswords: true))
        #expect(script == """
        printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\n' > /etc/ssh/sshd_config.d/000-lostty.conf
        chmod 644 /etc/ssh/sshd_config.d/000-lostty.conf
        """)
    }

    @Test func bothInOnePromptAndNothingWhenNothingIsNeeded() throws {
        let both = try #require(PhoneAccessAdmin.setupScript(enableRemoteLogin: true, lockPasswords: true))
        #expect(both.split(separator: "\n").count == 4)
        #expect(PhoneAccessAdmin.setupScript(enableRemoteLogin: false, lockPasswords: false) == nil)
        #expect(PhoneAccessAdmin.unlockScript == "rm -f /etc/ssh/sshd_config.d/000-lostty.conf")
    }

    @Test func appleScriptEscapesQuotesAndBackslashes() {
        let source = PhoneAccessAdmin.appleScript(running: #"printf 'a\nb' > "x""#, prompt: #"Say "hi""#)
        #expect(source == #"do shell script "printf 'a\\nb' > \"x\"" with prompt "Say \"hi\"" with administrator privileges"#)
    }
}
#endif
