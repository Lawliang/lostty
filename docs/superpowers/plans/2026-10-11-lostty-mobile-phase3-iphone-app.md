# Lostty Mobile Phase 3: iPhone App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iPhone app, built from the existing `Ghostty-iOS` target, that lists the Mac's Lostty tmux sessions by project name, opens one in the real Lostty terminal over SSH, takes typing from the soft keyboard plus a key row (Esc, sticky Ctrl, Tab, ⇧Tab, arrows, `/ @ ! |`), scrolls, closes a session on request, and reconnects by itself after the app comes back to the foreground or the network changes.

**Architecture:** Phase 2 already proved the core's remote backend and the `LosttyRemote` SSH package on the Mac. This phase reuses both unchanged in shape: `RemoteSurfaceIO` becomes cross-platform and gains `restart()`; the UIKit `SurfaceView` attaches a remote IO, accepts keyboard input through a shared, unit-tested `Ghostty.MobileInput` mapping (so the core's encoder still applies terminal modes), and hosts a key row as its keyboard accessory. SwiftUI screens on top: session list (home), settings, terminal.

**Tech Stack:** Swift 5 mode, SwiftUI + UIKit (iOS 17), GhosttyKit.xcframework (ios-arm64, ios-arm64-simulator slices already built), LosttyRemote (Citadel 0.12.1), CryptoKit Secure Enclave + LocalAuthentication, Network (`NWPathMonitor`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (§1 Mac host, §5 iPhone app, Build order step 3; the phase 1 and phase 2 "As built" notes in §2 and §4 and their deferred lists).

## Global Constraints

- Scope is Build order step 3: terminal, SSH, session list, key row, reconnect. Skins, Claude trace/usage and notifications on the phone are phase 4; do not port them.
- Session list is the home screen; under the hood it is `tmux -L lostty list-sessions`. Sessions are shown by project name (the tmux session name) and targeted by id `$N`.
- Key row above the keyboard: Esc, Ctrl (sticky), Tab, arrows, and keys Claude Code uses often — this plan's set: Esc, Ctrl, Tab, ⇧Tab, ←, ↓, ↑, →, `/`, `@`, `!`, `|`.
- Close-session action kills the tmux session (`tmux -u -L lostty kill-session -t '$N'`), behind a confirmation, because it also closes that session's Mac window.
- Leaving the terminal screen (back) closes only the SSH channel; the session keeps running.
- Reconnect on app foreground and on network change (spec §4), plus phase 2's backoff after a drop.
- All typing goes through `ghostty_surface_key` (never straight to SSH), so application cursor keys and the kitty keyboard protocol keep working.
- Auth: the Secure Enclave key behind Face ID. One Face ID approval covers every connection until the app goes to the background (a shared `LAContext`). Simulator builds (no Secure Enclave) use a software P-256 key stored in the app's Application Support with 0600 permissions — simulator only (`#if targetEnvironment(simulator)`).
- Host keys pinned on first connect (phase 2 `KnownHosts`, with IPv6 hosts bracketed in the label); a mismatch is a hard stop with a clear message.
- The phone never starts a tmux server and never attaches with `-d` (phase 2's commands already guarantee both).
- iOS app identity: display name "Lostty", bundle id `com.lawliang.lostty-mobile`, `NSFaceIDUsageDescription` = "Lostty uses Face ID to unlock the key it signs in to your Mac with."; deployment iOS 17.0 (unchanged).
- New iOS-only source files are wrapped in `#if os(iOS)` (the macOS target compiles every file under `macos/Sources` except an exception list). Shared logic that must be unit-tested lives in files compiled by both targets and is tested from `GhosttyTests` (macOS).
- Tests: package `cd macos/LosttyRemote && swift test`; app suites `macos/skins-test.sh <Suite>` (run `zig build -Demit-macos-app=false` first). iOS build check: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build` (the xcframework has no x86_64 simulator slice, hence `ARCHS=arm64`). The Mac Debug app must still build.
- Never touch `~/.ssh`, System Settings, sshd config, or tmux sessions on the `lostty` socket from an implementer task; those are desk steps for the human.
- Commits: stage files by path (never `default.profraw`); end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. swiftlint is not installed.

## Review Focus

1. **Typing on the phone must behave like the desk.** Ctrl+C must reach Claude as an interrupt, arrows must move in Claude's menus, Shift+Tab must cycle Claude's mode, and an uppercase letter or emoji must arrive as typed. Pinned by `MobileInputTests` (Task 1).
2. **Coming back to the app after it sat in the background** (the socket is dead but nothing has noticed): the terminal reattaches within a second, without the window closing or the user tapping anything. Pinned by `RemoteSurfaceIOTests.restartWhileAttached…` and `…restartDuringBackoff…` (Task 3).
3. **Settings typed on a phone keyboard** (trailing spaces, empty user, port out of range, an IPv6 Tailscale address): a usable error or a correct connection, never a crash or a pin for the wrong host. Pinned by `RemoteHostSettingsTests` and `KnownHostsTests.ipv6HostsDoNotCollide` (Task 2).
4. **Closing a session is destructive** (it also closes the Mac window): it must ask first and target the session by id, and an already-ended session must not be an error. Pinned by `TmuxRemoteTests.killQuotesTheSessionID` and `RemoteConnection.killSession` treating exit 1 as done (Task 2), and the confirmation dialog (Task 5, desk).
5. **Face ID once, not per connection.** Listing then opening a session, and every reconnect while in the foreground, must not prompt again. Pinned by `RemoteKey` taking a shared `LAContext` (Task 2) and the store holding one context per foreground period (Task 5, desk).

---

## File Structure

| File | Responsibility |
|---|---|
| `macos/Sources/Ghostty/Ghostty.MobileInput.swift` (new, both targets) | Phone input → key presses: typed text, key row keys, sticky Ctrl. |
| `macos/Tests/Remote/MobileInputTests.swift` (new) | Its tests (macOS host). |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteHostSettings.swift` (new) | The phone's saved host: validation, persistence. |
| `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift` | + `killCommand`, + `RemoteSession.forPicking`. |
| `macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift` | Bracket IPv6 hosts in the label. |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift` | + shared `LAContext`, + simulator software key. |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift` | + `killSession`. |
| `macos/Sources/Features/Remote/RemoteSurfaceIO.swift` | Cross-platform; + `restart()`. |
| `macos/Sources/Ghostty/Ghostty.App.swift` | iOS `wakeup` ticks the app; iOS `closeSurface` posts a notification. |
| `macos/Sources/Ghostty/Surface View/SurfaceView_UIKit.swift` | Remote IO attach/detach, keyboard input, key row accessory, scroll, tap to type. |
| `macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift` (new, iOS) | The key row view. |
| `macos/Sources/App/iOS/iOSApp.swift` | Root is the session list; lifecycle hooks. |
| `macos/Sources/App/iOS/MobileStore.swift` (new, iOS) | Settings, key, sessions, open/close, reconnect triggers. |
| `macos/Sources/App/iOS/SessionsScreen.swift`, `SettingsScreen.swift`, `TerminalScreen.swift` (new, iOS) | The three screens. |
| `macos/Ghostty.xcodeproj/project.pbxproj` | Link LosttyRemote into Ghostty-iOS; bundle id, display name, Face ID text. |
| `docs/lostty-mobile-host-setup.md` (new) | The Mac host checklist (spec §1) for the human. |

---

### Task 1: Phone input mapping

**Files:**
- Create: `macos/Sources/Ghostty/Ghostty.MobileInput.swift`
- Test: `macos/Tests/Remote/MobileInputTests.swift`

**Interfaces:**
- Produces:
  - `Ghostty.MobileInput.Press: Equatable` — `key: Ghostty.Input.Key?`, `mods: Ghostty.Input.Mods`, `text: String?`, `unshifted: UInt32`; `func withCValue<T>(action: ghostty_input_action_e, _ body: (ghostty_input_key_s) -> T) -> T`; `static let noKeycode: UInt32 = 0xFFFF`.
  - `Ghostty.MobileInput.RowKey: String, CaseIterable, Identifiable` — cases `esc, ctrl, tab, shiftTab, left, down, up, right, slash, at, bang, pipe`; `var label: String`.
  - `static func presses(typed: String, ctrl: Bool) -> [Press]`, `static func press(for: RowKey, ctrl: Bool) -> Press?` (nil for `.ctrl`, which latches), `static let backspace: Press`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Remote/MobileInputTests.swift`:

```swift
import GhosttyKit
import Testing
@testable import Ghostty

private typealias MI = Ghostty.MobileInput
private typealias P = Ghostty.MobileInput.Press

struct MobileInputTests {
    @Test func lowercaseLetterIsItsKeyWithText() {
        #expect(MI.presses(typed: "a", ctrl: false) == [P(key: .a, mods: [], text: "a", unshifted: 0x61)])
    }

    @Test func uppercaseLetterIsShiftedWithItsText() {
        #expect(MI.presses(typed: "Q", ctrl: false) == [P(key: .q, mods: .shift, text: "Q", unshifted: 0x71)])
    }

    @Test func ctrlLetterHasNoTextSoTheEncoderSendsAControlCode() {
        #expect(MI.presses(typed: "c", ctrl: true) == [P(key: .c, mods: .ctrl, text: nil, unshifted: 0x63)])
    }

    @Test func ctrlAppliesToTheFirstCharacterOnly() {
        #expect(MI.presses(typed: "cd", ctrl: true) == [
            P(key: .c, mods: .ctrl, text: nil, unshifted: 0x63),
            P(key: .d, mods: [], text: "d", unshifted: 0x64),
        ])
    }

    @Test func digitsSpaceAndReturn() {
        #expect(MI.presses(typed: "1 \n", ctrl: false) == [
            P(key: .digit1, mods: [], text: "1", unshifted: 0x31),
            P(key: .space, mods: [], text: " ", unshifted: 0x20),
            P(key: .enter, mods: [], text: nil, unshifted: 0),
        ])
    }

    @Test func punctuationAndEmojiAreTextWithNoKey() {
        #expect(MI.presses(typed: "/", ctrl: false) == [P(key: nil, mods: [], text: "/", unshifted: 0x2F)])
        #expect(MI.presses(typed: "👍", ctrl: false) == [P(key: nil, mods: [], text: "👍", unshifted: 0x1F44D)])
        // A character made of several scalars (flag) keeps its text whole.
        #expect(MI.presses(typed: "🇯🇵", ctrl: false) == [P(key: nil, mods: [], text: "🇯🇵", unshifted: 0)])
    }

    @Test func keyRowKeys() {
        #expect(MI.press(for: .esc, ctrl: false) == P(key: .escape, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .tab, ctrl: false) == P(key: .tab, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .shiftTab, ctrl: false) == P(key: .tab, mods: .shift, text: nil, unshifted: 0))
        #expect(MI.press(for: .up, ctrl: false) == P(key: .arrowUp, mods: [], text: nil, unshifted: 0))
        #expect(MI.press(for: .left, ctrl: true) == P(key: .arrowLeft, mods: .ctrl, text: nil, unshifted: 0))
        #expect(MI.press(for: .slash, ctrl: false) == P(key: nil, mods: [], text: "/", unshifted: 0x2F))
        #expect(MI.press(for: .at, ctrl: false) == P(key: nil, mods: [], text: "@", unshifted: 0x40))
        #expect(MI.press(for: .ctrl, ctrl: false) == nil)
    }

    @Test func backspace() {
        #expect(MI.backspace == P(key: .backspace, mods: [], text: nil, unshifted: 0))
    }

    @Test func cValueUsesTheKeysKeycodeOrNone() {
        let a = P(key: .a, mods: .ctrl, text: nil, unshifted: 0x61)
        a.withCValue(action: GHOSTTY_ACTION_PRESS) { c in
            #expect(c.keycode == UInt32(Ghostty.Input.Key.a.keyCode!))
            #expect(c.mods == Ghostty.Input.Mods.ctrl.cMods)
            #expect(c.text == nil)
            #expect(c.unshifted_codepoint == 0x61)
        }
        let slash = P(key: nil, mods: [], text: "/", unshifted: 0x2F)
        slash.withCValue(action: GHOSTTY_ACTION_PRESS) { c in
            #expect(c.keycode == P.noKeycode)
            #expect(String(cString: c.text!) == "/")
        }
    }

    @Test func everyRowKeyHasALabel() {
        for key in MI.RowKey.allCases { #expect(!key.label.isEmpty) }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `zig build -Demit-macos-app=false && macos/skins-test.sh MobileInputTests`
Expected: FAIL to compile — `Ghostty.MobileInput` not found.

- [ ] **Step 3: Write `Ghostty.MobileInput.swift`**

```swift
import GhosttyKit

extension Ghostty {
    /// Lostty Mobile: turns phone input — soft-keyboard text, the key row and
    /// a sticky Ctrl — into key presses for `ghostty_surface_key`, so the
    /// core's encoder still applies the terminal's modes (application cursor
    /// keys, the kitty keyboard protocol). Shared with the macOS target only
    /// so it can be unit-tested there.
    enum MobileInput {
        /// One key press.
        struct Press: Equatable {
            /// nil: a character with no key of its own (punctuation, emoji).
            var key: Input.Key?
            var mods: Input.Mods = []
            /// The text the key produces; nil when Ctrl is held, so the
            /// encoder sends the control code for `unshifted`.
            var text: String?
            var unshifted: UInt32 = 0

            /// A keycode no keyboard uses: the core treats the press as an
            /// unidentified key and sends its text.
            static let noKeycode: UInt32 = 0xFFFF

            func withCValue<T>(action: ghostty_input_action_e, _ body: (ghostty_input_key_s) -> T) -> T {
                var event = ghostty_input_key_s()
                event.action = action
                event.keycode = key.flatMap { $0.keyCode.map(UInt32.init) } ?? Self.noKeycode
                event.mods = mods.cMods
                event.consumed_mods = Input.Mods().cMods
                event.unshifted_codepoint = unshifted
                event.composing = false
                guard let text else {
                    event.text = nil
                    return body(event)
                }
                return text.withCString { ptr in
                    event.text = ptr
                    return body(event)
                }
            }
        }

        enum RowKey: String, CaseIterable, Identifiable {
            case esc, ctrl, tab, shiftTab, left, down, up, right, slash, at, bang, pipe

            var id: String { rawValue }

            var label: String {
                switch self {
                case .esc: "esc"
                case .ctrl: "ctrl"
                case .tab: "tab"
                case .shiftTab: "⇧tab"
                case .left: "←"
                case .down: "↓"
                case .up: "↑"
                case .right: "→"
                case .slash: "/"
                case .at: "@"
                case .bang: "!"
                case .pipe: "|"
                }
            }
        }

        static let backspace = Press(key: .backspace)

        /// Presses for text the soft keyboard inserted. `ctrl` (the sticky
        /// key) applies to the first character only.
        static func presses(typed text: String, ctrl: Bool) -> [Press] {
            text.enumerated().map { index, character in
                press(for: character, ctrl: ctrl && index == 0)
            }
        }

        /// The press for a key-row key; nil for Ctrl, which only latches.
        static func press(for key: RowKey, ctrl: Bool) -> Press? {
            let mods: Input.Mods = ctrl ? .ctrl : []
            switch key {
            case .ctrl: return nil
            case .esc: return Press(key: .escape, mods: mods)
            case .tab: return Press(key: .tab, mods: mods)
            case .shiftTab: return Press(key: .tab, mods: mods.union(.shift))
            case .left: return Press(key: .arrowLeft, mods: mods)
            case .down: return Press(key: .arrowDown, mods: mods)
            case .up: return Press(key: .arrowUp, mods: mods)
            case .right: return Press(key: .arrowRight, mods: mods)
            case .slash: return press(for: "/", ctrl: ctrl)
            case .at: return press(for: "@", ctrl: ctrl)
            case .bang: return press(for: "!", ctrl: ctrl)
            case .pipe: return press(for: "|", ctrl: ctrl)
            }
        }

        private static let letterKeys: [Character: Input.Key] = Dictionary(uniqueKeysWithValues: zip(
            "abcdefghijklmnopqrstuvwxyz",
            [Input.Key.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
             .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z]))

        private static let digitKeys: [Character: Input.Key] = Dictionary(uniqueKeysWithValues: zip(
            "0123456789",
            [Input.Key.digit0, .digit1, .digit2, .digit3, .digit4,
             .digit5, .digit6, .digit7, .digit8, .digit9]))

        private static func press(for character: Character, ctrl: Bool) -> Press {
            let ctrlMods: Input.Mods = ctrl ? .ctrl : []
            if character == "\n" || character == "\r" { return Press(key: .enter, mods: ctrlMods) }
            if character == "\t" { return Press(key: .tab, mods: ctrlMods) }

            let lower = Character(character.lowercased())
            if let key = letterKeys[lower], let scalar = lower.unicodeScalars.first {
                let shifted: Input.Mods = character == lower ? [] : .shift
                return Press(
                    key: key,
                    mods: ctrlMods.union(shifted),
                    text: ctrl ? nil : String(character),
                    unshifted: scalar.value)
            }
            if let key = digitKeys[character] ?? (character == " " ? .space : nil),
               let scalar = character.unicodeScalars.first {
                return Press(key: key, mods: ctrlMods, text: ctrl ? nil : String(character), unshifted: scalar.value)
            }

            // Everything else is text: punctuation, accents, emoji.
            let scalars = character.unicodeScalars
            return Press(key: nil, text: String(character), unshifted: scalars.count == 1 ? scalars.first!.value : 0)
        }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `macos/skins-test.sh MobileInputTests`
Expected: `** TEST SUCCEEDED **`. Also check the iOS target still compiles (the file is shared):
`xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '\*\* BUILD|error:'` → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Ghostty/Ghostty.MobileInput.swift macos/Tests/Remote/MobileInputTests.swift
git commit -m "lostty: phone input maps typed text, the key row and sticky Ctrl to key presses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: LosttyRemote for the phone — settings, kill, IPv6 pins, Face ID once, simulator key

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/RemoteHostSettings.swift`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift`, `KnownHosts.swift`, `RemoteKey.swift`, `RemoteConnection.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteHostSettingsTests.swift` (new); add to `TmuxRemoteTests.swift`, `KnownHostsTests.swift`, `RemoteKeyTests.swift`

**Interfaces:**
- Consumes: phase 2's `RemoteHost`, `RemoteSession`, `TmuxRemote.pathPrefix`, `TmuxRemote.isSessionID`, `TmuxRemote.shellQuote`, `TmuxRemoteError.badSessionID`, `KnownHosts`, `RemoteKey`, `RemoteConnection`.
- Produces:
  - `public struct RemoteHostSettings: Codable, Equatable, Sendable { host: String; port: Int; user: String; terminfoDir: String; static let defaultsKey = "LosttyRemoteHost"; static let defaultTerminfoDir = "/Applications/Lostty.app/Contents/Resources/terminfo"; var problem: String?; var remoteHost: RemoteHost?; static func load(from: UserDefaults) -> RemoteHostSettings; func save(to: UserDefaults) }`
  - `TmuxRemote.killCommand(sessionID: String) throws -> String`; `RemoteSession.forPicking(_ sessions: [RemoteSession]) -> [RemoteSession]` (static, sorted by name, then id).
  - `RemoteKey.secureEnclave(storedAt: URL, context: LAContext?) throws -> RemoteKey` (the phase 2 one-argument call keeps working via a default `nil`); `RemoteKey.software(storedAt: URL) throws -> RemoteKey`.
  - `RemoteConnection.killSession(_ sessionID: String) async throws` (exit 1 — already gone — is success).

- [ ] **Step 1: Write the failing tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteHostSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct RemoteHostSettingsTests {
    @Test func trimsWhatAPhoneKeyboardAdds() {
        let s = RemoteHostSettings(host: " my-mac.tail1234.ts.net ", port: 22, user: "lawliang ", terminfoDir: RemoteHostSettings.defaultTerminfoDir)
        #expect(s.problem == nil)
        #expect(s.remoteHost == RemoteHost(host: "my-mac.tail1234.ts.net", port: 22, user: "lawliang", terminfoDir: RemoteHostSettings.defaultTerminfoDir))
    }

    @Test func incompleteSettingsSayWhatIsMissing() {
        #expect(RemoteHostSettings(host: "", port: 22, user: "me", terminfoDir: "/t").problem == "Enter the Mac's address.")
        #expect(RemoteHostSettings(host: "mac", port: 22, user: " ", terminfoDir: "/t").problem == "Enter your user name on the Mac.")
        #expect(RemoteHostSettings(host: "mac", port: 0, user: "me", terminfoDir: "/t").problem == "The port must be between 1 and 65535.")
        #expect(RemoteHostSettings(host: "mac", port: 70000, user: "me", terminfoDir: "/t").remoteHost == nil)
        #expect(RemoteHostSettings(host: "mac mini", port: 22, user: "me", terminfoDir: "/t").problem == "The Mac's address can't contain spaces.")
    }

    @Test func savesAndLoads() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        #expect(RemoteHostSettings.load(from: defaults) == RemoteHostSettings())
        let s = RemoteHostSettings(host: "100.101.102.103", port: 2222, user: "me", terminfoDir: "/t")
        s.save(to: defaults)
        #expect(RemoteHostSettings.load(from: defaults) == s)
    }

    @Test func loadsAJSONStringSoALaunchArgumentCanSetIt() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        defaults.set(#"{"host":"localhost","port":22,"user":"me","terminfoDir":"/t"}"#, forKey: RemoteHostSettings.defaultsKey)
        #expect(RemoteHostSettings.load(from: defaults).host == "localhost")
    }

    @Test func defaultsAreEmptyWithTheStandardTerminfo() {
        let s = RemoteHostSettings()
        #expect(s.host.isEmpty && s.user.isEmpty && s.port == 22)
        #expect(s.terminfoDir == "/Applications/Lostty.app/Contents/Resources/terminfo")
    }
}
```

Append to `TmuxRemoteTests.swift` (inside the struct):

```swift
    @Test func killQuotesTheSessionID() throws {
        #expect(try TmuxRemote.killCommand(sessionID: "$4") ==
            "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty kill-session -t '$4'")
        #expect(throws: TmuxRemoteError.badSessionID("main")) { try TmuxRemote.killCommand(sessionID: "main") }
    }

    @Test func sessionsArePickedByProjectName() {
        let s = [
            RemoteSession(id: "$3", name: "zeta", surface: nil, owner: nil),
            RemoteSession(id: "$1", name: "Alpha", surface: nil, owner: nil),
            RemoteSession(id: "$2", name: "beta", surface: "X", owner: 42),
        ]
        #expect(RemoteSession.forPicking(s).map(\.id) == ["$1", "$2", "$3"])
    }
```

Append to `KnownHostsTests.swift` (inside the struct):

```swift
    @Test func ipv6HostsDoNotCollide() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "fd7a:115c:a1e0::1", port: 22, key: "K1")
        // "fd7a:115c:a1e0::1:22" on port 22 must not read as the host above on another port.
        #expect(hosts.verdict(host: "fd7a:115c:a1e0::1:22", port: 22, key: "K1") == .unknown)
        #expect(hosts.verdict(host: "fd7a:115c:a1e0::1", port: 22, key: "K1") == .trusted)
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("[fd7a:115c:a1e0::1]:22 "))
    }
```

Append to `RemoteKeyTests.swift` (in `RemoteKeyTests`):

```swift
    @Test func softwareKeyIsCreatedOnceAndKept() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-swkey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = try RemoteKey.software(storedAt: file)
        let again = try RemoteKey.software(storedAt: file)
        #expect(first.publicKeyLine == again.publicKeyLine)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func aCorruptSoftwareKeyFileIsNotReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-swkey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("junk".utf8).write(to: file)
        #expect(throws: (any Error).self) { try RemoteKey.software(storedAt: file) }
        #expect(try Data(contentsOf: file) == Data("junk".utf8))
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd macos/LosttyRemote && swift test 2>&1 | tail -5`
Expected: FAIL to compile — `RemoteHostSettings`, `killCommand`, `forPicking`, `RemoteKey.software` not found.

- [ ] **Step 3: Write `RemoteHostSettings.swift`**

```swift
import Foundation

/// The Mac the phone connects to, as typed in Settings. Stored in
/// UserDefaults as JSON under `defaultsKey`; a JSON string is accepted too,
/// so a launch argument (`-LosttyRemoteHost '{"host":…}'`) can set it.
public struct RemoteHostSettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "LosttyRemoteHost"
    public static let defaultTerminfoDir = "/Applications/Lostty.app/Contents/Resources/terminfo"

    public var host: String
    public var port: Int
    public var user: String
    /// Lostty.app's terminfo directory on the Mac (xterm-ghostty).
    public var terminfoDir: String

    public init(host: String = "", port: Int = 22, user: String = "", terminfoDir: String = RemoteHostSettings.defaultTerminfoDir) {
        self.host = host
        self.port = port
        self.user = user
        self.terminfoDir = terminfoDir
    }

    /// What to fix before connecting, or nil.
    public var problem: String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Enter the Mac's address." }
        if host.contains(where: \.isWhitespace) { return "The Mac's address can't contain spaces." }
        if user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your user name on the Mac." }
        if !(1...65535).contains(port) { return "The port must be between 1 and 65535." }
        return nil
    }

    public var remoteHost: RemoteHost? {
        guard problem == nil else { return nil }
        let dir = terminfoDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteHost(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            user: user.trimmingCharacters(in: .whitespacesAndNewlines),
            terminfoDir: dir.isEmpty ? Self.defaultTerminfoDir : dir)
    }

    public static func load(from defaults: UserDefaults) -> RemoteHostSettings {
        let data = defaults.data(forKey: defaultsKey) ?? defaults.string(forKey: defaultsKey).map { Data($0.utf8) }
        guard let data, let settings = try? JSONDecoder().decode(RemoteHostSettings.self, from: data) else {
            return RemoteHostSettings()
        }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Add kill and picking order to `TmuxRemote.swift`**

Inside `public enum TmuxRemote`, after `attachCommand`:

```swift
    /// Ends session `sessionID` (and with it the Mac window showing it).
    public static func killCommand(sessionID: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return "\(pathPrefix) tmux -u -L lostty kill-session -t \(shellQuote(sessionID))"
    }
```

After `public struct RemoteSession { … }`:

```swift
extension RemoteSession {
    /// The order the session list shows: by project name, as Finder sorts.
    public static func forPicking(_ sessions: [RemoteSession]) -> [RemoteSession] {
        sessions.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
```

- [ ] **Step 5: Bracket IPv6 hosts in `KnownHosts.swift`**

Replace `private static func label(_ host: String, _ port: Int) -> String { "\(host):\(port)" }` with:

```swift
    /// "host:port", with IPv6 hosts bracketed ("[fd7a::1]:22") so the port
    /// can't be read as part of the address.
    private static func label(_ host: String, _ port: Int) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
```

- [ ] **Step 6: Face ID once and the simulator key in `RemoteKey.swift`**

Add `import LocalAuthentication` at the top. Change the Secure Enclave loader to take an optional context (keep its body's phase 2 behaviour: create only when the file is absent, throw when it exists but can't be loaded):

```swift
    /// Loads the key whose handle is at `url`, creating it on first use.
    /// Signing asks for Face ID / Touch ID through `context`: pass the same
    /// `LAContext` for every connection and it asks once, until the context
    /// is invalidated (the app invalidates it when it goes to the background).
    public static func secureEnclave(storedAt url: URL, context: LAContext? = nil) throws -> RemoteKey {
```

and inside it use `SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data, authenticationContext: context)` for loading and `SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: context)` for creating.

Add after it:

```swift
    /// A software key for the iOS simulator, which has no Secure Enclave.
    /// Stored raw with 0600 permissions; never used on a device.
    public static func software(storedAt url: URL) throws -> RemoteKey {
        if FileManager.default.fileExists(atPath: url.path) {
            return RemoteKey(software: try P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: url)))
        }
        let key = P256.Signing.PrivateKey()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.rawRepresentation.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return RemoteKey(software: key)
    }
```

- [ ] **Step 7: `killSession` in `RemoteConnection.swift`**

After `sessions()`:

```swift
    /// Ends session `sessionID` on the Mac. A session that already ended
    /// (tmux exits 1) is not an error.
    public func killSession(_ sessionID: String) async throws {
        do {
            _ = try await client.executeCommand(try TmuxRemote.killCommand(sessionID: sessionID))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            return
        }
    }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd macos/LosttyRemote && swift build 2>&1 | grep -E 'error|warning: ' ; swift test 2>&1 | tail -3`
Expected: no errors; all tests pass (phase 2's plus the new ones). Then make sure the Mac app still builds (it calls `RemoteKey.secureEnclave(storedAt:)`): `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | grep -E '\*\* BUILD|error:'` → `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote macos/LosttyRemote/Tests/LosttyRemoteTests
git commit -m "lostty: LosttyRemote for the phone: host settings, kill session, IPv6 pins, one Face ID per session, simulator key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `RemoteSurfaceIO` on iOS, with `restart()`

**Files:**
- Modify: `macos/Sources/Features/Remote/RemoteSurfaceIO.swift`
- Modify: `macos/Sources/Features/Remote/RemoteDebugUI.swift` (the one `SSHAttacher(…)` call: `key: { key }`)
- Test: `macos/Tests/Remote/RemoteSurfaceIOTests.swift`

**Interfaces:**
- Consumes: phase 2's `RemoteSurfaceIO`, `RemoteAttacher`, `SSHAttacher`.
- Produces: `RemoteSurfaceIO` and `SSHAttacher` compiled for iOS too (`SSHAttacher` becomes `@available(macOS 15, iOS 17, *)`); `func restart()` on `RemoteSurfaceIO`; `SSHAttacher.key` becomes a provider, `let key: @Sendable () async throws -> RemoteKey`, called once per attempt (the phone replaces its key after the app was in the background, and an attacher holding the old key would sign with an invalidated Face ID context).

`restart()` contract: when the loop is attached, close the current terminal and attach again at once — the end of that attach is neither an exit (the pane must not close) nor a disconnect notice; when the loop is waiting in backoff, cut the wait short and attach now; after `detach` or before `attach(to:)`, do nothing. Backoff restarts from its first delay.

- [ ] **Step 1: Write the failing tests**

Add to `RemoteSurfaceIOTests.swift` (helpers at file scope, tests inside `struct RemoteSurfaceIOTests`):

```swift
/// Each attach opens a terminal and stays attached until that terminal is
/// closed, then returns `.exited(0)` — as a real channel does on a local
/// close. Records how many attaches ran.
private final class CloseEndsAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _attaches = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var attaches: Int { lock.withLock { _attaches } }

    final class Terminal: RemoteTerminal, @unchecked Sendable {
        let onClose: @Sendable () -> Void
        init(onClose: @escaping @Sendable () -> Void) { self.onClose = onClose }
        func write(_ data: Data) {}
        func resize(cols: Int, rows: Int) {}
        func close() { onClose() }
    }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        lock.withLock { _attaches += 1 }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let once = OnceFlag()
            onOpen(Terminal { if once.claim() { done.resume() } })
        }
        return .exited(0)
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
}

private func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
}
```

```swift
    @Test func restartWhileAttachedReattachesWithoutClosingThePane() async throws {
        let log = SurfaceLog()
        let attacher = CloseEndsAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { attacher.attaches == 1 }
        io.restart()
        try await waitUntil { attacher.attaches == 2 }
        #expect(attacher.attaches == 2)
        #expect(log.events.isEmpty, "a restart is neither an exit nor a disconnect")
        io.detach()
        await io.finished()
    }

    @Test func restartDuringBackoffAttachesNow() async throws {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in
            try await Task.sleep(for: .seconds(60))
        }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { log.events == ["disconnected"] }
        io.restart()
        await io.finished()
        #expect(attacher.sizes.count == 2)
        #expect(log.events == ["disconnected", "exited 0"])
    }

    @Test func restartAfterDetachDoesNothing() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.detach()
        io.restart()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.isEmpty)
    }
```

(`SurfaceLog`, `ScriptedAttacher`, `fakeSurface` already exist in the file from phase 2; if the current `ScriptedAttacher` or `SurfaceLog` API differs, adapt the calls, not the assertions.)

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh RemoteSurfaceIOTests`
Expected: FAIL to compile — `restart()` not found.

- [ ] **Step 3: Make it cross-platform and add `restart()`**

1. Remove the file's outer `#if os(macOS)` / `#endif`. Change `@available(macOS 15, *)` on `SSHAttacher` to `@available(macOS 15, iOS 17, *)`. Make its key a provider:
```swift
    /// The key, fetched for each attempt: the phone replaces its key (and
    /// Face ID context) after the app has been in the background.
    let key: @Sendable () async throws -> RemoteKey
```
   and in `attach` use `try await RemoteConnection.connect(to: host, key: try await key(), knownHosts: knownHosts)`. Update the call in `RemoteDebugUI.swift` to pass `key: { key }`.
2. Add state (guarded by `stateLock`):
```swift
    /// Set by `restart()`: the current attach's end is a restart, not an
    /// exit or a drop.
    private var restartRequested = false
    /// The backoff wait in progress, so `restart()` can cut it short.
    private var delay: Task<Void, Error>?
```
3. Add:
```swift
    /// Drops the connection and attaches again at once. For the phone
    /// coming back to the foreground or changing networks, when the old
    /// connection may be dead without anyone having noticed. Does nothing
    /// before `attach(to:)` or after `detach()`.
    func restart() {
        let open: RemoteTerminal? = stateLock.withLock {
            guard !detached, task != nil else { return nil }
            restartRequested = true
            delay?.cancel()
            return terminal
        }
        open?.close()
    }

    /// Waits `seconds` (the backoff), ending early on `restart()`. False
    /// when the pane is gone.
    private func pause(_ seconds: TimeInterval) async -> Bool {
        let wait = Task { try await delays(seconds) }
        stateLock.withLock { delay = wait }
        _ = try? await wait.value
        stateLock.withLock { delay = nil }
        return !Task.isCancelled
    }

    /// Consumes a pending restart request.
    private func takeRestart() -> Bool {
        stateLock.withLock {
            defer { restartRequested = false }
            return restartRequested
        }
    }
```
4. In `pause`, clear the request when the wait ends — a restart during the wait has done its job by ending it: replace `stateLock.withLock { delay = nil }` with `stateLock.withLock { delay = nil; restartRequested = false }`.
5. In `run()`:
   - replace each `guard (try? await delays(policy.nextDelay())) != nil else { return }` with `guard await pause(policy.nextDelay()) else { return }`;
   - in the generic `catch` (failed connect), after `closed()` and the cancellation check, before pausing: `if takeRestart() { policy.reset(); continue }`;
   - after an attach returns (after `if Task.isCancelled { return }` and `closed()`), before the `switch end`: `if takeRestart() { policy.reset(); continue }` — so a restart is never reported as `.exited` or `.lost`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh RemoteSurfaceIOTests`
Expected: `** TEST SUCCEEDED **` (phase 2's tests plus the three new ones).

Then the iOS target must still compile with the file now included:
`xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '\*\* BUILD|error:'`
Expected: it fails with "No such module 'LosttyRemote'" — that is fixed in Task 4 Step 1. If you want a green iOS build here, do Task 4 Step 1 (linking the package into Ghostty-iOS) first and say so in the report; nothing else from Task 4.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Remote/RemoteSurfaceIO.swift macos/Tests/Remote/RemoteSurfaceIOTests.swift
git commit -m "lostty: remote bridge builds for iOS and can restart a connection that may be dead

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The iOS terminal — remote surface, keyboard, key row, scrolling

**Files:**
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj` (link LosttyRemote into Ghostty-iOS; bundle id; display name; Face ID text)
- Modify: `macos/Sources/Ghostty/Ghostty.App.swift` (iOS `wakeup`, `closeSurface`)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_UIKit.swift`
- Create: `macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift`

**Interfaces:**
- Consumes: `Ghostty.MobileInput` (Task 1); `RemoteSurfaceIO` (Task 3); `Ghostty.RemoteIO`, `SurfaceConfiguration.remoteIO` (phase 2).
- Produces:
  - `Notification.Name.losttySurfaceClosed` (iOS; `object` is the `Ghostty.SurfaceView`).
  - iOS `Ghostty.SurfaceView`: becomes first responder on tap and shows the keyboard with the key row; `func showKeyboard()`; scrolling by pan.
  - `Ghostty.KeyRowView: UIInputView` (iOS).

- [ ] **Step 1: Project settings**

In `macos/Ghostty.xcodeproj/project.pbxproj`:

1. Confirm `grep -c 4C5A0005 macos/Ghostty.xcodeproj/project.pbxproj` prints `0`. Add a build file in `/* Begin PBXBuildFile section */`:
```
		4C5A00052F7A000000C0FFEE /* LosttyRemote in Frameworks */ = {isa = PBXBuildFile; productRef = 4C5A00062F7A000000C0FFEE /* LosttyRemote */; };
```
2. In the Ghostty-iOS Frameworks phase (`A5D4499A2B53AE7B000F5B83 /* Frameworks */`), after the GhosttyKit line:
```
				4C5A00052F7A000000C0FFEE /* LosttyRemote in Frameworks */,
```
3. In the Ghostty-iOS target (`A5D4499C2B53AE7B000F5B83`), add after `name = "Ghostty-iOS";`:
```
			packageProductDependencies = (
				4C5A00062F7A000000C0FFEE /* LosttyRemote */,
			);
```
4. In `/* Begin XCSwiftPackageProductDependency section */` add:
```
		4C5A00062F7A000000C0FFEE /* LosttyRemote */ = {
			isa = XCSwiftPackageProductDependency;
			package = 4C5A00032F7A000000C0FFEE /* XCLocalSwiftPackageReference "LosttyRemote" */;
			productName = LosttyRemote;
		};
```
5. In the three Ghostty-iOS build configurations (`A5D449A82B53AE7B000F5B83` Debug, `A5D449A92B53AE7B000F5B83` Release, `A5D449AA2B53AE7B000F5B83` ReleaseLocal):
   - `PRODUCT_BUNDLE_IDENTIFIER = "com.mitchellh.ghostty-ios";` → `PRODUCT_BUNDLE_IDENTIFIER = "com.lawliang.lostty-mobile";`
   - `INFOPLIST_KEY_CFBundleDisplayName = Ghostty;` → `INFOPLIST_KEY_CFBundleDisplayName = Lostty;`
   - add `INFOPLIST_KEY_NSFaceIDUsageDescription = "Lostty uses Face ID to unlock the key it signs in to your Mac with.";` right after the display-name line.

   Do it with a script that edits only those three blocks:
```bash
python3 - <<'EOF'
import re
p = 'macos/Ghostty.xcodeproj/project.pbxproj'
s = open(p).read()
for cid in ['A5D449A82B53AE7B000F5B83', 'A5D449A92B53AE7B000F5B83', 'A5D449AA2B53AE7B000F5B83']:
    m = re.search(r'\t\t' + cid + r' /\* \w+ \*/ = \{.*?\n\t\t\};', s, re.S)
    b = m.group(0)
    assert 'com.mitchellh.ghostty-ios' in b and 'INFOPLIST_KEY_CFBundleDisplayName = Ghostty;' in b, cid
    nb = b.replace('"com.mitchellh.ghostty-ios"', '"com.lawliang.lostty-mobile"')
    nb = nb.replace('INFOPLIST_KEY_CFBundleDisplayName = Ghostty;',
        'INFOPLIST_KEY_CFBundleDisplayName = Lostty;\n\t\t\t\tINFOPLIST_KEY_NSFaceIDUsageDescription = "Lostty uses Face ID to unlock the key it signs in to your Mac with.";')
    s = s.replace(b, nb)
open(p, 'w').write(s)
EOF
```

- [ ] **Step 2: iOS app callbacks in `Ghostty.App.swift`**

In the `#if os(iOS)` callback block, replace the `wakeup` and `closeSurface` stubs:

```swift
        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            // Lostty Mobile: process the core's messages (as on macOS).
            guard let userdata else { return }
            let state = Unmanaged<App>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { state.appTick() }
        }
```

```swift
        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            // Lostty Mobile: a remote session ended; the screen showing it
            // goes back to the session list.
            guard let userdata else { return }
            let view = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            NotificationCenter.default.post(name: .losttySurfaceClosed, object: view)
        }
```

and at the end of the file:

```swift
#if os(iOS)
extension Notification.Name {
    /// Lostty Mobile: a surface's program ended; `object` is its SurfaceView.
    static let losttySurfaceClosed = Notification.Name("LosttySurfaceClosed")
}
#endif
```

- [ ] **Step 3: Write `KeyRow_UIKit.swift`**

```swift
#if os(iOS)
import UIKit

extension Ghostty {
    /// Lostty Mobile: the key row above the keyboard. Ctrl latches for the
    /// next key and shows it.
    final class KeyRowView: UIInputView {
        var onKey: ((MobileInput.RowKey) -> Void)?
        private var ctrlButton: UIButton?

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
            allowsSelfSizing = true
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            for key in MobileInput.RowKey.allCases {
                let button = UIButton(type: .system)
                button.setTitle(key.label, for: .normal)
                button.titleLabel?.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 5
                button.accessibilityLabel = key.rawValue
                button.addAction(UIAction { [weak self] _ in self?.onKey?(key) }, for: .touchUpInside)
                if key == .ctrl { ctrlButton = button }
                stack.addArrangedSubview(button)
            }
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
                heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        /// Shows whether Ctrl is latched.
        func setCtrl(_ on: Bool) {
            ctrlButton?.backgroundColor = on ? .tintColor : .secondarySystemBackground
            ctrlButton?.setTitleColor(on ? .white : nil, for: .normal)
        }
    }
}
#endif
```

- [ ] **Step 4: Remote IO, keyboard and scrolling in `SurfaceView_UIKit.swift`**

1. Add stored properties next to `private(set) var surface`:
```swift
        /// Lostty Mobile: the remote IO of a remote surface.
        private let remoteIO: RemoteIO?
        /// The sticky Ctrl from the key row, used by the next key.
        var ctrlLatched = false {
            didSet { keyRow.setCtrl(ctrlLatched) }
        }
        private lazy var keyRow: KeyRowView = {
            let row = KeyRowView()
            row.onKey = { [weak self] key in self?.rowKey(key) }
            return row
        }()
        /// Scroll distance not yet sent, in points.
        private var pendingScroll: CGFloat = 0
```
2. In `init`, before `super.init`: `self.remoteIO = baseConfig?.remoteIO`. After `self.surface = surface`:
```swift
            // Lostty Mobile: a remote surface starts its session now.
            remoteIO?.attach(to: surface)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
```
3. Replace `deinit` with:
```swift
        deinit {
            // Lostty Mobile: stop feeding before the surface is freed. Freeing
            // joins the core's threads, so no callback reaches remoteIO after.
            remoteIO?.detach()
            guard let surface = self.surface else { return }
            ghostty_surface_free(surface)
        }
```
4. Add, in the `// MARK: UIView` section:
```swift
        override var canBecomeFirstResponder: Bool { true }
        override var inputAccessoryView: UIView? { keyRow }

        func showKeyboard() {
            _ = becomeFirstResponder()
        }

        @objc private func tapped() {
            showKeyboard()
        }

        /// A vertical pan scrolls (tmux turns the wheel into its scrollback).
        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            guard let surface else { return }
            pendingScroll += pan.translation(in: self).y
            pan.setTranslation(.zero, in: self)
            let line = max(cellSize.height / contentScaleFactor, 8)
            let lines = (pendingScroll / line).rounded(.towardZero)
            guard lines != 0 else { return }
            pendingScroll -= lines * line
            ghostty_surface_mouse_scroll(surface, 0, Double(lines), 0)
        }

        func send(_ presses: [MobileInput.Press]) {
            guard let surface else { return }
            for press in presses {
                press.withCValue(action: GHOSTTY_ACTION_PRESS) { _ = ghostty_surface_key(surface, $0) }
                press.withCValue(action: GHOSTTY_ACTION_RELEASE) { _ = ghostty_surface_key(surface, $0) }
            }
        }

        private func rowKey(_ key: MobileInput.RowKey) {
            if key == .ctrl {
                ctrlLatched.toggle()
                return
            }
            let ctrl = ctrlLatched
            ctrlLatched = false
            if let press = MobileInput.press(for: key, ctrl: ctrl) { send([press]) }
        }
```
5. After the class, add the keyboard conformance:
```swift
extension Ghostty.SurfaceView: UIKeyInput {
    // Always true, so the keyboard's delete key always reaches us.
    var hasText: Bool { true }

    // UITextInputTraits: a terminal wants exactly what was typed. Declared
    // here, with the conformance, so UIKit sees them.
    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
    var smartDashesType: UITextSmartDashesType { get { .no } set {} }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { get { .no } set {} }
    var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }
    var keyboardAppearance: UIKeyboardAppearance { get { .dark } set {} }

    func insertText(_ text: String) {
        let ctrl = ctrlLatched
        ctrlLatched = false
        send(Ghostty.MobileInput.presses(typed: text, ctrl: ctrl))
    }

    func deleteBackward() {
        send([Ghostty.MobileInput.backspace])
    }
}
```
(`send` and `ctrlLatched` are internal, not `private`, because the extension uses them.)

Note on scrolling: the core's scroll API takes a delta in lines in the direction the content should move; if the desk check finds the direction inverted, negate `lines` (a one-character fix the desk task will catch).

- [ ] **Step 5: Build the iOS app and run the Mac suites**

Run:
```bash
zig build -Demit-macos-app=false
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '\*\* BUILD|error:'
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | grep -E '\*\* BUILD|error:'
for s in MobileInputTests RemoteSurfaceIOTests; do macos/skins-test.sh $s | tail -1; done
```
Expected: both builds `** BUILD SUCCEEDED **`, both suites `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Ghostty.xcodeproj/project.pbxproj macos/Sources/Ghostty/Ghostty.App.swift \
  "macos/Sources/Ghostty/Surface View/SurfaceView_UIKit.swift" "macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift"
git commit -m "lostty: iOS terminal takes remote IO, the soft keyboard, a key row and scrolling; app is Lostty

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The iPhone screens and reconnect triggers

**Files:**
- Create: `macos/Sources/App/iOS/MobileStore.swift`, `SessionsScreen.swift`, `SettingsScreen.swift`, `TerminalScreen.swift`
- Modify: `macos/Sources/App/iOS/iOSApp.swift`

**Interfaces:**
- Consumes: `RemoteHostSettings`, `RemoteSession.forPicking`, `RemoteConnection.connect/sessions/killSession/close`, `RemoteKey.secureEnclave(storedAt:context:)`, `RemoteKey.software(storedAt:)`, `KnownHosts`, `RemoteError.message` (Task 2, phase 2); `RemoteSurfaceIO`, `SSHAttacher`, `restart()` (Task 3); `Ghostty.SurfaceView`, `showKeyboard()`, `.losttySurfaceClosed`, `Ghostty.SurfaceRepresentable` (Task 4).
- Produces: the app.

- [ ] **Step 1: Write `MobileStore.swift`**

```swift
#if os(iOS)
import Foundation
import GhosttyKit
import LocalAuthentication
import LosttyRemote
import Network
import SwiftUI

/// Lostty Mobile's state: the Mac to reach, the key, the session list, and
/// the open terminal's connection, which it restarts when the app returns
/// to the foreground or the network changes.
@MainActor
final class MobileStore: ObservableObject {
    @Published var settings: RemoteHostSettings
    @Published private(set) var sessions: [RemoteSession] = []
    @Published private(set) var loading = false
    @Published var message: String?

    /// One Face ID approval per foreground period.
    private var context = LAContext()
    private var key: RemoteKey?
    private let defaults: UserDefaults
    private var openIO: RemoteSurfaceIO?
    private let pathMonitor = NWPathMonitor()
    private var sawFirstPath = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = RemoteHostSettings.load(from: defaults)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path.status) }
        }
        pathMonitor.start(queue: .main)
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty", isDirectory: true)
    }

    var knownHosts: KnownHosts { KnownHosts(fileURL: Self.supportDir.appendingPathComponent("known_hosts")) }

    func saveSettings() {
        settings.save(to: defaults)
    }

    /// The SSH key, loaded once; Face ID is asked through the shared context.
    func remoteKey() throws -> RemoteKey {
        if let key { return key }
        #if targetEnvironment(simulator)
        let loaded = try RemoteKey.software(storedAt: Self.supportDir.appendingPathComponent("simulator-key"))
        #else
        let loaded = try RemoteKey.secureEnclave(storedAt: Self.supportDir.appendingPathComponent("remote-key"), context: context)
        #endif
        key = loaded
        return loaded
    }

    func refresh() async {
        guard let host = settings.remoteHost else {
            message = settings.problem
            return
        }
        loading = true
        defer { loading = false }
        do {
            let connection = try await RemoteConnection.connect(to: host, key: try remoteKey(), knownHosts: knownHosts)
            defer { Task { await connection.close() } }
            sessions = RemoteSession.forPicking(try await connection.sessions())
            message = sessions.isEmpty ? "No Lostty sessions are running on the Mac." : nil
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
        }
    }

    func kill(_ session: RemoteSession) async {
        guard let host = settings.remoteHost else { return }
        do {
            let connection = try await RemoteConnection.connect(to: host, key: try remoteKey(), knownHosts: knownHosts)
            try await connection.killSession(session.id)
            await connection.close()
            sessions.removeAll { $0.id == session.id }
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
        }
    }

    /// A terminal view attached to `session`; nil (with a message) when the
    /// settings or key aren't ready.
    func terminal(for session: RemoteSession, app: ghostty_app_t) -> Ghostty.SurfaceView? {
        guard let host = settings.remoteHost else {
            message = settings.problem
            return nil
        }
        do {
            _ = try remoteKey()  // surface a key problem now, not after the screen opens
            let io = RemoteSurfaceIO(attacher: SSHAttacher(
                host: host,
                key: { [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.remoteKey()
                },
                knownHosts: knownHosts,
                sessionID: session.id))
            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = io
            openIO = io
            return Ghostty.SurfaceView(app, baseConfig: config)
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func terminalClosed() {
        openIO = nil
    }

    // MARK: Reconnect triggers

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            openIO?.restart()
        case .background:
            // Face ID again after the app has been away.
            context.invalidate()
            context = LAContext()
            key = nil
        default:
            break
        }
    }

    /// Any network update after the first (Wi-Fi ↔ cellular, a new
    /// address) may have killed the connection: attach again.
    private func networkChanged(_ status: NWPath.Status) {
        defer { sawFirstPath = true }
        guard sawFirstPath, status == .satisfied else { return }
        openIO?.restart()
    }
}
#endif
```

- [ ] **Step 2: Write `SettingsScreen.swift`**

```swift
#if os(iOS)
import LosttyRemote
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?

    var body: some View {
        Form {
            Section("Mac") {
                TextField("Address (Tailscale name or IP)", text: $store.settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("User", text: $store.settings.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: $store.settings.port, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Lostty terminfo on the Mac", text: $store.settings.terminfoDir)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            }
            if let problem = store.settings.problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            Section {
                Button("Show This Phone's Key") {
                    publicKey = (try? store.remoteKey())?.publicKeyLine
                }
                if let publicKey {
                    Text(publicKey).font(.footnote.monospaced()).textSelection(.enabled)
                    ShareLink(item: publicKey)
                }
            } header: {
                Text("Key")
            } footer: {
                Text("Add this line to ~/.ssh/authorized_keys on the Mac.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            Button("Done") {
                store.saveSettings()
                dismiss()
            }
        }
    }
}
#endif
```

- [ ] **Step 3: Write `TerminalScreen.swift`**

```swift
#if os(iOS)
import LosttyRemote
import SwiftUI

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking.
struct TerminalScreen: View {
    let session: RemoteSession
    let surfaceView: Ghostty.SurfaceView
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClose = false

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Close Session", role: .destructive) { confirmClose = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog(
            "Close \(session.name)?", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("Close Session", role: .destructive) {
                Task {
                    await store.kill(session)
                    dismiss()
                }
            }
        } message: {
            Text("This ends the session on the Mac and closes its window there.")
        }
        .onAppear { surfaceView.showKeyboard() }
        .onDisappear { store.terminalClosed() }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView { dismiss() }
        }
    }
}
#endif
```

- [ ] **Step 4: Write `SessionsScreen.swift`**

```swift
#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions by project name.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView)?
    @State private var showSettings = false
    @State private var confirmKill: RemoteSession?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let message = store.message {
                    Text(message).foregroundStyle(.secondary)
                }
                ForEach(store.sessions, id: \.id) { session in
                    Button {
                        guard let app = ghostty.app, let view = store.terminal(for: session, app: app) else { return }
                        open = (session, view)
                        path = ["terminal"]
                    } label: {
                        HStack {
                            Text(session.name).font(.body.monospaced())
                            Spacer()
                            if session.owner != nil {
                                Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                                    .accessibilityLabel("Open on the Mac")
                            }
                        }
                    }
                    .swipeActions {
                        Button("Close", role: .destructive) { confirmKill = session }
                    }
                }
            }
            .overlay { if store.loading && store.sessions.isEmpty { ProgressView() } }
            .refreshable { await store.refresh() }
            .navigationTitle("Lostty")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .navigationDestination(for: String.self) { _ in
                if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await store.refresh() } }) {
                NavigationStack { SettingsScreen() }
            }
            .confirmationDialog(
                "Close \(confirmKill?.name ?? "")?",
                isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } }),
                titleVisibility: .visible
            ) {
                Button("Close Session", role: .destructive) {
                    if let session = confirmKill { Task { await store.kill(session) } }
                }
            } message: {
                Text("This ends the session on the Mac and closes its window there.")
            }
            .task { await store.refresh() }
            .onChange(of: path) { _, newPath in
                // Back from the terminal: drop it, and refresh the list.
                if newPath.isEmpty {
                    open = nil
                    Task { await store.refresh() }
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 5: Make the session list the app's root in `iOSApp.swift`**

Replace `Ghostty_iOSApp`'s stored property and body with:

```swift
@main
struct Ghostty_iOSApp: App {
    @StateObject private var ghostty_app: Ghostty.App
    // Lostty Mobile: sessions, settings, key and reconnects.
    @StateObject private var store = MobileStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            preconditionFailure("Initialize ghostty backend failed")
        }
        _ghostty_app = StateObject(wrappedValue: Ghostty.App())
    }

    var body: some Scene {
        WindowGroup {
            SessionsScreen()
                .environmentObject(ghostty_app)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in store.scenePhaseChanged(phase) }
    }
}
```

Leave `iOS_GhosttyTerminal` and `iOS_GhosttyInitView` in place (unused).

- [ ] **Step 6: Build, then see it run in the simulator**

Run:
```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '\*\* BUILD|error:'
SIM=$(xcrun simctl list devices | grep -m1 'Lostty iPhone' | grep -oE '[0-9A-F-]{36}') || true
[ -n "$SIM" ] || SIM=$(xcrun simctl create "Lostty iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-26-3)
xcrun simctl boot "$SIM" 2>/dev/null; xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" macos/build/Debug-iphonesimulator/Ghostty-iOS.app
xcrun simctl launch "$SIM" com.lawliang.lostty-mobile -LosttyRemoteHost '{"host":"localhost","port":22,"user":"nobody-lostty-test","terminfoDir":"/t"}'
sleep 6; xcrun simctl io "$SIM" screenshot /tmp/lostty-sim-home.png
```
Expected: build succeeds; the app launches; the screenshot (open it with an image viewer or the Read tool) shows the "Lostty" title and either a connection/auth error message or "No Lostty sessions…" — not a crash and not a blank screen. Do not add any key to `~/.ssh/authorized_keys`; the full simulator round trip is a desk step (Task 6).

Also confirm the Mac app and its suites are unaffected: Mac Debug build `** BUILD SUCCEEDED **`; `macos/skins-test.sh RemoteSurfaceIOTests` and `MobileInputTests` pass.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/App/iOS
git commit -m "lostty: iPhone app: session list, settings, terminal screen, close session, reconnect on foreground and network change

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Host setup notes, desk check, spec notes

**Files:**
- Create: `docs/lostty-mobile-host-setup.md`
- Modify: `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (§5: "As built (phase 3)")

- [ ] **Step 1: Write `docs/lostty-mobile-host-setup.md`**

```markdown
# Lostty Mobile: Mac host setup

Do these once on the Mac the phone connects to.

1. **tmux**: `brew install tmux` (phase 1 needs it too).
2. **Remote Login**: System Settings → General → Sharing → Remote Login on,
   "Allow access for" → only your user.
3. **Keys only** (no passwords over SSH): create
   `/etc/ssh/sshd_config.d/200-lostty.conf` containing
   ```
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   ```
   then toggle Remote Login off and on. Check with
   `ssh -o PreferredAuthentications=password localhost` — it must refuse.
4. **The phone's key**: in the phone app, Settings → Show This Phone's Key →
   share it to the Mac, and append the line to `~/.ssh/authorized_keys`
   (`chmod 600 ~/.ssh/authorized_keys`).
5. **Tailscale** on the Mac and the iPhone, signed in to the same tailnet,
   starting at login, with two-factor on the account. In the phone app use
   the Mac's Tailscale name (`your-mac.tailXXXX.ts.net`) or 100.x address.
6. **Awake in a bag** (optional): `sudo pmset -a disablesleep 1` keeps a
   closed MacBook awake (`sudo pmset -a disablesleep 0` to undo), or use
   Amphetamine with a battery floor. Set the Mac's Wi-Fi to auto-join the
   iPhone's hotspot. Expect heat under heavy builds and battery drain.
```

- [ ] **Step 2: Automated checks**

```bash
(cd macos/LosttyRemote && swift test 2>&1 | tail -1)
for s in MobileInputTests RemoteSurfaceIOTests TmuxSessionTests TmuxOwnershipTests TmuxPaneTests TmuxClientTests SessionLaunchTests SessionsPromptTests; do macos/skins-test.sh $s >/dev/null || echo "FAIL $s"; done
zig build test -Dtest-filter="lostty" && echo ZIG-OK
sh macos/lostty-tmux-smoke.sh | tail -1
```
Expected: package tests pass, no `FAIL`, `ZIG-OK`, `PASS`.

- [ ] **Step 3: STOP — desk check with your human partner**

A. Simulator round trip (the controller can drive it, with the human's OK to add the simulator's key): launch the simulator app with `-LosttyRemoteHost '{"host":"localhost","port":22,"user":"<their user>","terminfoDir":"/Applications/Lostty.app/Contents/Resources/terminfo"}'` (or the Debug app's terminfo path), open Settings → Show This Phone's Key, add it to `~/.ssh/authorized_keys` with their OK, pull to refresh: the Mac's sessions appear; tap one: the shell shows; type `echo sim` with the simulator keyboard.

B. On the iPhone (theirs to do: signing team, install, Mac setup from `docs/lostty-mobile-host-setup.md`):
1. In Xcode: open `macos/Ghostty.xcodeproj`, scheme Ghostty-iOS, Signing & Capabilities → Team = their personal team, select the iPhone, Run. (A free team needs re-installing every 7 days.)
2. Settings: the Mac's Tailscale name, user; Show This Phone's Key → add it on the Mac.
3. The list shows the Mac's sessions by project name; Face ID asks once.
4. Open one: the shell shows; the Mac window is the same session.
5. Type `ls` and return; uppercase and an emoji type correctly.
6. Key row: `ctrl` then `c` interrupts `sleep 100`; arrows move in `claude`'s menus; ⇧tab cycles Claude's mode; esc works.
7. Swipe up/down scrolls back through output and returns.
8. Back: the session keeps running (`tmux -L lostty ls` on the Mac); reopening it needs no new Face ID.
9. Home screen for a minute, back to the app: it reattaches by itself (Face ID once).
10. Switch Wi-Fi ↔ cellular while open: "reconnecting…", then it's back.
11. Close Session (confirm): the session ends and its Mac window closes.
12. `exit` in the shell: the phone goes back to the list.
13. Rotate to landscape: the terminal resizes (`tput cols` changes).

- [ ] **Step 4: Fix what fails** — each failure through a subagent with review, then repeat the check.

- [ ] **Step 5: Record how phase 3 was built**

Add "As built (phase 3)" to the end of spec §5: the screens; the key row's keys; input through `ghostty_surface_key` via `Ghostty.MobileInput`; one Face ID per foreground period; simulator software key; reconnect triggers (foreground, network change) via `RemoteSurfaceIO.restart()`; scrolling by pan → mouse wheel; bundle id and signing; desk outcomes; and what is deferred (hardware keyboard, copy/paste and selection, clipboard from OSC 52, titles, skins and Claude features are phase 4). Commit:

```bash
git add docs/lostty-mobile-host-setup.md docs/superpowers/specs/2026-10-09-lostty-mobile-design.md
git commit -m "docs: Lostty Mobile host setup, and how phase 3 was built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
