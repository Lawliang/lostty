# Lostty Mobile Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A developer goes from two installed apps to a working phone session with no typing: a Phone Access checklist on the Mac fixes setup (one admin prompt at most), the Mac shows a QR code, the phone scans it, sends its key over an encrypted nearby link, the Mac asks Allow, and the phone confirms with a real connection over Tailscale.

**Architecture:** Shared, unit-tested pieces live in the `LosttyRemote` package: the QR payload, the pairing link (Network framework, TLS with a pre-shared key derived from the QR's secret, Bonjour `_lostty-pair._tcp` with peer-to-peer), the pairing messages, `authorized_keys` editing, host-key pinning and host fallback. The Mac app adds a Phone Access window (checks that need no admin, one `NSAppleScript` admin prompt, the pairing server, the paired-phones list). The iPhone app adds a welcome screen, a QR scanner and a pairing flow, and moves the manual fields under Advanced. macOS's own sshd keeps doing every login.

**Tech Stack:** Swift 5 mode; SwiftUI + AppKit (macOS 14) and SwiftUI + UIKit + VisionKit (iOS 17); Network framework (`NWListener`, `NWBrowser`, `NWConnection`, `sec_protocol_options_add_pre_shared_key`); CryptoKit (HKDF, SHA-256); swift-nio-ssh via Citadel 0.12.1 (key parsing); CoreImage (QR); Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-lostty-mobile-onboarding-design.md`

## Global Constraints

- Nothing is hosted. Customers bring their own Tailscale. No new package dependencies.
- macOS's Remote Login (system sshd) does every login; Lostty writes no SSH server or authentication code.
- Password lockdown file: `/etc/ssh/sshd_config.d/000-lostty.conf` containing exactly `PasswordAuthentication no` and `KbdInteractiveAuthentication no`. Remote Login is turned on with `launchctl enable system/com.openssh.sshd` + `launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist`; never `systemsetup`.
- Phone key line in `~/.ssh/authorized_keys`: `restrict,pty <type> <base64> lostty-phone:<uuid>`. Lines Lostty did not add are never changed.
- QR payload: `lostty://pair?v=1&name=<MagicDNS name>&ip=<Tailscale IPv4>&user=<short user name>&hostkey=<ed25519 host key>&secret=<32 random bytes>` (binary fields base64url without padding in the URL).
- Pairing link: Bonjour service type `_lostty-pair._tcp`, service name = first 8 hex digits of SHA-256(secret), `includePeerToPeer = true`, TLS 1.2 PSK: key = HKDF-SHA256(secret, info `lostty-pair-v1`, 32 bytes), identity `lostty-pair`. One valid request per code; the Mac stops listening after it, on Cancel, or after 2 minutes; a new sheet makes a new secret.
- Only `ecdsa-sha2-nistp256` phone keys are accepted (Secure Enclave keys).
- Copy, verbatim from the spec:
  - Allow prompt: `Allow “<model>” to open your Lostty sessions?`
  - Awake note: `Your phone can reach this Mac only while it's awake.`
  - Skip warning: `Without this, anyone who can reach this Mac can try your password over SSH, on any network, for every account on this Mac. If you SSH into this Mac with a password from elsewhere, that keeps working.`
  - Phone: `This Mac's identity changed. If you reinstalled macOS, pair again; otherwise, don't connect.` / `Can't reach your Mac. Is Tailscale on here and on the Mac, and is the Mac awake?` / `Your Mac doesn't accept this phone anymore.` / `No sessions. Is Lostty open on your Mac?` / `Your Mac declined. Try again from Phone Access.` / `Is Tailscale on and signed into the same account as your Mac?`
- One Mac per phone; pairing again replaces it. Several phones per Mac.
- Face ID behaves as today (once per foreground period).
- New macOS-only files are wrapped in `#if os(macOS)`, iOS-only in `#if os(iOS)` (both app targets compile every file under `macos/Sources`).
- Implementer tasks never touch the real `~/.ssh`, `/etc/ssh`, `~/.terminfo`, System Settings, or tmux sessions, and never run the admin prompt. Tests use temp directories. Those steps are desk checks for the human (Task 9).
- Tests: package `cd macos/LosttyRemote && swift test --filter <Suite>`; app suites `macos/skins-test.sh <Suite>` (build `zig build -Demit-macos-app=false` first only if `macos/GhosttyKit.xcframework` is missing). iOS build check: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build`. The Mac Debug app must still build (`macos/build.nu --configuration Debug --action build`).
- Commits: stage files by path (never `default.profraw`); end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. swiftlint is not installed.

## Review Focus

1. **A nearby device without the QR code** (or a second scan of a used code) connects to the pairing listener: it must never reach the Allow prompt, must not use up the code, and must not stop the real phone from pairing. Pinned by `PairingChannelTests.aWrongCodeNeverReachesThePromptAndDoesNotUseUpTheCode` and `theCodeWorksOnce` (Task 1).
2. **The phone chooses the model text shown in the Allow prompt**: newlines, right-to-left overrides or 10,000 characters must come out as one short, plain line. Pinned by `PairingMessageTests.displayModelIsOneShortPlainLine` (Task 1).
3. **A customer's own `authorized_keys`** (comments, options, CRLF lines, no trailing newline, a symlink into a dotfiles repo, no `~/.ssh` yet) must keep every byte Lostty didn't write, end up 0600 in a 0700 directory, and stay a symlink. Pinned by `AuthorizedKeysTests` and `AuthorizedKeysFileTests` (Task 3).
4. **A customer sshd config that keeps password logins on despite Lostty's file** (an earlier drop-in, a `Match` block) must show as not done, never ✓. Pinned by `PhoneAccessChecksTests.passwordStillOfferedIsNotLockedDown` (Task 5) and `PhoneAccessRowsTests.lockdownFileButPasswordsStillOn` (Task 7).
5. **The Mac's Tailscale name doesn't resolve on the phone** (MagicDNS off): the phone must fall back to the IP; but a refused key, a changed host key or a cancelled Face ID must stop at once, never retry the other address. Pinned by `HostFallbackTests` (Task 4).

---

## File Structure

| File | Responsibility |
|---|---|
| `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingCrypto.swift` (new) | Secret → Bonjour name, PSK, Network parameters. |
| `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingMessage.swift` (new) | Request/response JSON; key and model validation. |
| `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingChannel.swift` (new) | Framing, `PairingServer` (Mac), `PairingClient` (phone), `PairingError`. |
| `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingPayload.swift` (new) | The QR payload: validate, encode, decode. |
| `macos/LosttyRemote/Sources/LosttyRemote/DeviceModel.swift` (new) | "iPhone14,5" → "iPhone 13". |
| `macos/LosttyRemote/Sources/LosttyRemote/AuthorizedKeys.swift` (new) | Pure `authorized_keys` text edits + atomic file writer. |
| `macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift` | + `pin` (replace). |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteHostSettings.swift` | − terminfo, + `fallbackHost`, `pairedAt`, `remoteHosts`, `paired(with:at:)`. |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift` | `terminfoDir` optional; + `connect(toFirstReachable:)`, `HostFallback`. |
| `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift` | Attach exports `TERMINFO` only when given. |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift` | iOS messages from the spec; `isUnreachable` public; `.notPaired`. |
| `macos/LosttyRemote/Tests/LosttyRemoteTests/*` | Tests for all of the above. |
| `macos/Sources/Features/Remote/RemoteSurfaceIO.swift` | `SSHAttacher` takes `hosts`. |
| `macos/Sources/Features/Remote/RemoteDebugUI.swift` | Passes `hosts: [host]`. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift` (new, macOS) | Status model, parsers, `Command`, terminfo install, probe. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessAdmin.swift` (new, macOS) | Admin scripts and the `NSAppleScript` prompt. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift` (new, macOS) | Rows, paired-phone names, host key read. Pure, tested. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift` (new, macOS) | Window state: refresh, fixes, pairing server, Allow, remove, turn off. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (new, macOS) | SwiftUI window and pairing sheet with the QR code. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessUI.swift` (new, macOS) | Menu item and window. |
| `macos/Sources/App/macOS/AppDelegate.swift` | Install the menu item. |
| `macos/Ghostty-Info.plist`, `macos/Ghostty.xcodeproj/project.pbxproj` | Bonjour service, local network text, iOS Info.plist and camera text. |
| `macos/Lostty-iOS-Info.plist` (new) | iOS `NSBonjourServices`. |
| `macos/Sources/App/iOS/MobileStore.swift` | Pairing flow, host fallback, Pair Again state. |
| `macos/Sources/App/iOS/WelcomeScreen.swift`, `PairingScreen.swift`, `QRScannerView.swift` (new, iOS) | First run and pairing UI. |
| `macos/Sources/App/iOS/SessionsScreen.swift`, `SettingsScreen.swift` | Welcome when unpaired, Pair Again, Advanced. |
| `macos/Tests/PhoneAccess/*` (new) | App-side tests. |
| `docs/lostty-mobile-phone-access.md` (new), `docs/lostty-mobile-host-setup.md` | Customer guide; manual setup marked Advanced. |

---

### Task 1: The pairing link (TLS with the QR's secret)

This is the riskiest piece (spec, Risks), so it goes first and is proven over loopback before any UI depends on it. **If the PSK handshake does not complete in the loopback tests, stop and report BLOCKED with the exact error; do not substitute another transport.**

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingCrypto.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingMessage.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingChannel.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/PairingMessageTests.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/PairingChannelTests.swift`

**Interfaces:**
- Produces:
  - `PairingCrypto.serviceType: String` (`"_lostty-pair._tcp"`), `serviceName(secret: Data) -> String`, `preSharedKey(secret: Data) -> SymmetricKey`, `parameters(secret: Data) -> NWParameters`.
  - `PairingRequest: Codable, Equatable, Sendable` — `v: Int`, `publicKey: String`, `model: String`; `init(publicKey:model:)`; `acceptedKey: String?`; `displayModel: String`.
  - `PairingResponse: Codable, Equatable, Sendable` — `v: Int`, `result: Result` (`.allowed`, `.denied`); `init(result:)`.
  - `PairingError: Error, Equatable` — `.invalidLink`, `.macNotFound`, `.localNetworkDenied`, `.connectionFailed`, `.badMessage`; `var message: String`.
  - `PairingServer` — `typealias Decide = @Sendable (PairingRequest) async -> Bool`; `init(secret: Data, advertise: Bool = true, decide: @escaping Decide, onFinish: @escaping @Sendable (Bool) -> Void = { _ in }) throws`; `func start() async throws -> NWEndpoint.Port`; `func stop()`.
  - `PairingClient.find(secret: Data, timeout: TimeInterval = 20) async throws -> NWEndpoint`; `PairingClient.send(_ request: PairingRequest, to: NWEndpoint, secret: Data, timeout: TimeInterval = 150) async throws -> PairingResponse`.

- [ ] **Step 1: Write the failing message tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/PairingMessageTests.swift`:

```swift
import Crypto
import Foundation
import NIOSSH
import Testing
@testable import LosttyRemote

struct PairingMessageTests {
    static let phoneKey = RemoteKey(software: P256.Signing.PrivateKey()).publicKeyLine

    @Test func acceptsAPhoneKeyAndDropsItsComment() throws {
        let request = PairingRequest(publicKey: Self.phoneKey, model: "iPhone 13")
        let accepted = try #require(request.acceptedKey)
        #expect(accepted.hasPrefix("ecdsa-sha2-nistp256 "))
        #expect(accepted.split(separator: " ").count == 2)
        #expect(Self.phoneKey.hasPrefix(accepted))
    }

    @Test func refusesOtherKeyTypesAndGarbage() {
        let ed = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        for key in [ed, "ecdsa-sha2-nistp256 notbase64!!", "ecdsa-sha2-nistp256", "", "ssh-rsa AAAAB3Nza"] {
            #expect(PairingRequest(publicKey: key, model: "x").acceptedKey == nil, "\(key)")
        }
    }

    @Test func displayModelIsOneShortPlainLine() {
        #expect(PairingRequest(publicKey: "", model: "iPhone 13").displayModel == "iPhone 13")
        #expect(PairingRequest(publicKey: "", model: "Evil\nAllow\tme").displayModel == "Evil Allow me")
        #expect(PairingRequest(publicKey: "", model: "a\u{202E}gnp.exe").displayModel == "agnp.exe")
        #expect(PairingRequest(publicKey: "", model: String(repeating: "x", count: 10_000)).displayModel.count == 40)
        #expect(PairingRequest(publicKey: "", model: " \n\u{0}").displayModel == "iPhone")
    }

    @Test func messagesRoundTripAsJSON() throws {
        let request = PairingRequest(publicKey: Self.phoneKey, model: "iPhone 13")
        #expect(try JSONDecoder().decode(PairingRequest.self, from: JSONEncoder().encode(request)) == request)
        #expect(request.v == 1)
        let response = PairingResponse(result: .denied)
        let json = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        #expect(json.contains("\"denied\""))
        #expect(try JSONDecoder().decode(PairingResponse.self, from: Data(json.utf8)) == response)
    }

    @Test func serviceNameIsEightHexDigitsAndFollowsTheSecret() {
        let a = PairingCrypto.serviceName(secret: Data(repeating: 1, count: 32))
        #expect(a.count == 8)
        #expect(a.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(a == PairingCrypto.serviceName(secret: Data(repeating: 1, count: 32)))
        #expect(a != PairingCrypto.serviceName(secret: Data(repeating: 2, count: 32)))
    }

    @Test func frameLengthsAreBounded() {
        #expect(PairingWire.bodyLength(header: PairingWire.frame(Data([1, 2, 3])).prefix(4)) == 3)
        #expect(PairingWire.bodyLength(header: Data([0, 0, 0, 0])) == nil)
        #expect(PairingWire.bodyLength(header: Data([0, 0, 0x10, 0x01])) == nil)  // 4097
        #expect(PairingWire.bodyLength(header: Data([0, 0, 1])) == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd macos/LosttyRemote && swift test --filter PairingMessageTests`
Expected: compile errors (`PairingRequest`, `PairingCrypto`, `PairingWire` not found).

- [ ] **Step 3: Write `PairingCrypto.swift` and `PairingMessage.swift`**

`macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingCrypto.swift`:

```swift
import CryptoKit
import Foundation
import Network

/// The QR code's one-time secret, turned into what both sides of a pairing
/// need: the Bonjour name the Mac advertises, and the TLS pre-shared key
/// that only the phone that scanned the code knows.
public enum PairingCrypto {
    public static let serviceType = "_lostty-pair._tcp"
    static let pskIdentity = "lostty-pair"

    /// First 8 hex digits of SHA-256(secret): finds the right Mac without
    /// advertising the secret.
    public static func serviceName(secret: Data) -> String {
        SHA256.hash(data: secret).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// HKDF-SHA256(secret, info "lostty-pair-v1"), 32 bytes.
    public static func preSharedKey(secret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            info: Data("lostty-pair-v1".utf8),
            outputByteCount: 32)
    }

    /// TCP + TLS 1.2 with only a PSK cipher suite, so a peer without the
    /// secret fails the handshake; peer-to-peer allowed, so pairing works on
    /// Wi-Fi that keeps devices apart.
    public static func parameters(secret: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = preSharedKey(secret: secret).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(
            options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }
}
```

This follows Apple's TicTacToe Network-framework sample. If the compiler reports that `tls_ciphersuite_t(rawValue:)` isn't optional, drop the `!`; if the cipher-suite constant is unavailable, use its value `0x00A8`. A crash at that line is the Step 7 BLOCKED case.

`macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingMessage.swift`:

```swift
import Foundation
import NIOSSH

/// Phone → Mac: the key to allow, and what to call the phone.
public struct PairingRequest: Codable, Equatable, Sendable {
    public var v: Int
    public var publicKey: String
    public var model: String

    public init(publicKey: String, model: String) {
        v = 1
        self.publicKey = publicKey
        self.model = model
    }

    /// "ecdsa-sha2-nistp256 AAAA…" (comment dropped) when the key parses as
    /// one; nil for any other type or a malformed key. Only Secure Enclave
    /// keys are ever paired.
    public var acceptedKey: String? {
        let fields = publicKey.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0] == "ecdsa-sha2-nistp256" else { return nil }
        let line = "\(fields[0]) \(fields[1])"
        guard (try? NIOSSHPublicKey(openSSHPublicKey: line)) != nil else { return nil }
        return line
    }

    /// The model for the Allow prompt. The phone chooses this text, so
    /// control and format characters are dropped, whitespace collapsed, and
    /// it is cut to 40 characters; "iPhone" when nothing is left.
    public var displayModel: String {
        let kept = model.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }
        let words = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let short = String(words.prefix(40))
        return short.isEmpty ? "iPhone" : short
    }
}

/// Mac → phone.
public struct PairingResponse: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case allowed
        case denied
    }

    public var v: Int
    public var result: Result

    public init(result: Result) {
        v = 1
        self.result = result
    }
}
```

(Newlines and tabs are kept by the filter only so the whitespace split turns them into single spaces; every other control or format character, such as U+202E, is dropped.)

- [ ] **Step 4: Write `PairingChannel.swift`**

`macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingChannel.swift`:

```swift
import Foundation
import Network

public enum PairingError: Error, Equatable {
    case invalidLink
    case macNotFound
    case localNetworkDenied
    case connectionFailed
    case badMessage

    public var message: String {
        switch self {
        case .invalidLink:
            "That isn't a Lostty pairing code. On your Mac, open Lostty → Phone Access → Pair a Phone."
        case .macNotFound:
            "Couldn't find your Mac nearby. Keep the pairing code open on the Mac, and keep this phone close to it."
        case .localNetworkDenied:
            "Lostty needs Local Network access to find your Mac. Turn it on in Settings → Privacy & Security → Local Network, then try again."
        case .connectionFailed:
            "The connection to your Mac dropped. Show a new code on the Mac and scan it again."
        case .badMessage:
            "Your Mac answered in a way this Lostty doesn't understand. Update Lostty on both devices."
        }
    }
}

/// Runs a closure at most once, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// Length-prefixed JSON messages (4-byte big-endian length, at most 4 KiB).
enum PairingWire {
    static let maxMessage = 4096

    static func frame(_ body: Data) -> Data {
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    /// The body length a header announces; nil for 0, over `maxMessage`, or
    /// a short header.
    static func bodyLength(header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        return (1...maxMessage).contains(length) ? length : nil
    }

    /// Starts `connection` and waits for the TLS handshake. Any failure,
    /// including a wrong pre-shared key, is `.connectionFailed`.
    static func start(_ connection: NWConnection, queue: DispatchQueue) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { done.resume() }
                case .failed, .waiting, .cancelled: once.run { done.resume(throwing: PairingError.connectionFailed) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func send(_ body: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection.send(content: frame(body), completion: .contentProcessed { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            })
        }
    }

    static func receive(on connection: NWConnection) async throws -> Data {
        guard let length = bodyLength(header: try await read(4, on: connection)) else {
            throw PairingError.badMessage
        }
        return try await read(length, on: connection)
    }

    /// Exactly `count` bytes; cancelling the connection ends a pending read.
    private static func read(_ count: Int, on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let data, data.count == count {
                    done.resume(returning: data)
                } else {
                    done.resume(throwing: error ?? PairingError.connectionFailed)
                }
            }
        }
    }
}

/// The Mac's side of pairing. A device without the QR code fails the TLS
/// handshake and never gets a request in, so it can't use up the code. The
/// first valid request is answered (after `decide`), then the server stops.
public final class PairingServer: @unchecked Sendable {
    public typealias Decide = @Sendable (PairingRequest) async -> Bool

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.server")
    private let decide: Decide
    private let onFinish: @Sendable (Bool) -> Void
    private let lock = NSLock()
    private var claimed = false
    private var connections: [NWConnection] = []

    /// `advertise`: publish the Bonjour service (tests connect by port instead).
    public init(
        secret: Data,
        advertise: Bool = true,
        decide: @escaping Decide,
        onFinish: @escaping @Sendable (Bool) -> Void = { _ in }
    ) throws {
        listener = try NWListener(using: PairingCrypto.parameters(secret: secret))
        if advertise {
            listener.service = NWListener.Service(
                name: PairingCrypto.serviceName(secret: secret), type: PairingCrypto.serviceType)
        }
        self.decide = decide
        self.onFinish = onFinish
    }

    /// Starts listening; the port once ready.
    public func start() async throws -> NWEndpoint.Port {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let once = Once()
        let listener = listener
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<NWEndpoint.Port, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { done.resume(returning: listener.port ?? .any) }
                case .failed, .cancelled: once.run { done.resume(throwing: PairingError.connectionFailed) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Stops listening and drops every open connection.
    public func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections = []
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        let done = claimed
        if !done { connections.append(connection) }
        lock.unlock()
        guard !done else {
            connection.cancel()
            return
        }
        Task { await self.serve(connection) }
    }

    /// The first valid request claims the code.
    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    private func serve(_ connection: NWConnection) async {
        do {
            try await PairingWire.start(connection, queue: queue)
            let request = try JSONDecoder().decode(PairingRequest.self, from: try await PairingWire.receive(on: connection))
            guard request.v == 1 else { throw PairingError.badMessage }
            guard claim() else {
                connection.cancel()
                return
            }
            let allowed = request.acceptedKey == nil ? false : await decide(request)
            let response = try JSONEncoder().encode(PairingResponse(result: allowed ? .allowed : .denied))
            try? await PairingWire.send(response, on: connection)
            stop()
            onFinish(allowed)
        } catch {
            connection.cancel()
        }
    }
}

/// The phone's side of pairing.
public enum PairingClient {
    /// Finds the Mac showing this code nearby (same Wi-Fi, or peer-to-peer).
    public static func find(secret: Data, timeout: TimeInterval = 20) async throws -> NWEndpoint {
        let wanted = PairingCrypto.serviceName(secret: secret)
        let browser = NWBrowser(
            for: .bonjour(type: PairingCrypto.serviceType, domain: nil),
            using: PairingCrypto.parameters(secret: secret))
        let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.browse")
        let once = Once()
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<NWEndpoint, Error>) in
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint, name == wanted {
                        once.run {
                            browser.cancel()
                            done.resume(returning: result.endpoint)
                        }
                        return
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error) where isPolicyDenied(error), .failed(let error) where isPolicyDenied(error):
                    once.run {
                        browser.cancel()
                        done.resume(throwing: PairingError.localNetworkDenied)
                    }
                case .failed:
                    once.run {
                        browser.cancel()
                        done.resume(throwing: PairingError.macNotFound)
                    }
                default:
                    break
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                once.run {
                    browser.cancel()
                    done.resume(throwing: PairingError.macNotFound)
                }
            }
        }
    }

    /// Sends `request` to the Mac and waits for its answer while the Allow
    /// prompt is up, at most `timeout` (then the connection is cancelled,
    /// which ends the pending read).
    public static func send(
        _ request: PairingRequest,
        to endpoint: NWEndpoint,
        secret: Data,
        timeout: TimeInterval = 150
    ) async throws -> PairingResponse {
        let queue = DispatchQueue(label: "com.lawliang.lostty.pairing.client")
        let connection = NWConnection(to: endpoint, using: PairingCrypto.parameters(secret: secret))
        let deadline = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            connection.cancel()
        }
        try await PairingWire.start(connection, queue: queue)
        try await PairingWire.send(try JSONEncoder().encode(request), on: connection)
        let response = try JSONDecoder().decode(PairingResponse.self, from: try await PairingWire.receive(on: connection))
        guard response.v == 1 else { throw PairingError.badMessage }
        return response
    }

    /// iOS reports a denied Local Network permission as DNS-SD's
    /// kDNSServiceErr_PolicyDenied (-65570).
    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }
        return false
    }
}
```

- [ ] **Step 5: Run the message tests**

Run: `cd macos/LosttyRemote && swift test --filter PairingMessageTests`
Expected: all pass.

- [ ] **Step 6: Write the failing loopback tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/PairingChannelTests.swift`:

```swift
import Crypto
import Foundation
import Network
import Testing
@testable import LosttyRemote

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Real TLS-PSK over loopback: proves the handshake, the framing, and that
/// only the right secret gets a request in.
@Suite(.serialized) struct PairingChannelTests {
    static let phoneKey = RemoteKey(software: P256.Signing.PrivateKey()).publicKeyLine
    let secret = Data(repeating: 7, count: 32)

    func listen(_ decide: @escaping PairingServer.Decide) async throws -> (PairingServer, NWEndpoint) {
        let server = try PairingServer(secret: secret, advertise: false, decide: decide)
        let port = try await server.start()
        return (server, .hostPort(host: "127.0.0.1", port: port))
    }

    @Test func theRightCodeGetsAnAnswer() async throws {
        let seen = Box<PairingRequest?>(nil)
        let (server, endpoint) = try await listen { request in
            seen.value = request
            return true
        }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "iPhone 13")
        let response = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .allowed)
        #expect(seen.value == request)
    }

    @Test func aWrongCodeNeverReachesThePromptAndDoesNotUseUpTheCode() async throws {
        let asked = Box(0)
        let (server, endpoint) = try await listen { _ in
            asked.value += 1
            return true
        }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "x")
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(request, to: endpoint, secret: Data(repeating: 8, count: 32), timeout: 5)
        }
        #expect(asked.value == 0)
        let response = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .allowed)
        #expect(asked.value == 1)
    }

    @Test func denyIsReported() async throws {
        let (server, endpoint) = try await listen { _ in false }
        defer { server.stop() }
        let response = try await PairingClient.send(
            PairingRequest(publicKey: Self.phoneKey, model: "x"), to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .denied)
    }

    @Test func aKeyThatIsNotAPhoneKeyIsDeniedWithoutAsking() async throws {
        let asked = Box(0)
        let (server, endpoint) = try await listen { _ in
            asked.value += 1
            return true
        }
        defer { server.stop() }
        let response = try await PairingClient.send(
            PairingRequest(publicKey: "ssh-rsa AAAAB3NzaC1yc2E", model: "x"), to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .denied)
        #expect(asked.value == 0)
    }

    @Test func theCodeWorksOnce() async throws {
        let (server, endpoint) = try await listen { _ in true }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "x")
        #expect(try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10).result == .allowed)
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 5)
        }
    }

    @Test func aMacThatNeverAnswersTimesOut() async throws {
        let (server, endpoint) = try await listen { _ in
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        defer { server.stop() }
        let start = Date()
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(
                PairingRequest(publicKey: Self.phoneKey, model: "x"), to: endpoint, secret: secret, timeout: 2)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
```

- [ ] **Step 7: Run the loopback tests**

Run: `cd macos/LosttyRemote && swift test --filter PairingChannelTests`
Expected: all 6 pass. If `theRightCodeGetsAnAnswer` fails with a TLS or handshake error, this is the spec's top risk: stop and report BLOCKED with the full output (do not change the transport).

- [ ] **Step 8: Run the whole package suite**

Run: `cd macos/LosttyRemote && swift test`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/Pairing macos/LosttyRemote/Tests/LosttyRemoteTests/PairingMessageTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/PairingChannelTests.swift
git commit -m "lostty: pairing link over TLS with the QR code's secret

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The QR payload and the phone's model name

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingPayload.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/DeviceModel.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/PairingPayloadTests.swift`

**Interfaces:**
- Consumes: `PairingError.invalidLink` (Task 1).
- Produces:
  - `PairingPayload: Equatable, Sendable` — `name`, `ip`, `user`, `hostKey` (standard base64), `secret: Data`; `init(name:ip:user:hostKey:secret:) throws` (validates); `init(url: URL) throws`; `var url: URL`; `var hostKeyLine: String` (`"ssh-ed25519 <hostKey>"`); `static func newSecret() -> Data`.
  - `DeviceModel.name(forIdentifier: String) -> String`; on iOS `DeviceModel.current: String`.

- [ ] **Step 1: Write the failing tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/PairingPayloadTests.swift`:

```swift
import Crypto
import Foundation
import NIOSSH
import Testing
@testable import LosttyRemote

struct PairingPayloadTests {
    static let hostKey: String = {
        let line = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        return String(line.split(separator: " ")[1])
    }()

    /// Bytes whose base64 contains "+" and "/", which a URL must not mangle.
    static let secret = Data((0..<32).map { $0 % 2 == 0 ? 0xFB : 0xFF })

    func payload(
        name: String = "laws-macbook-pro.tail278d1f.ts.net", ip: String = "100.126.63.10",
        user: String = "lawliang", hostKey: String = hostKey, secret: Data = secret
    ) throws -> PairingPayload {
        try PairingPayload(name: name, ip: ip, user: user, hostKey: hostKey, secret: secret)
    }

    @Test func roundTripsThroughItsURL() throws {
        let p = try payload()
        #expect(p.url.scheme == "lostty")
        #expect(p.url.host == "pair")
        #expect(p.url.absoluteString.contains("v=1"))
        #expect(try PairingPayload(url: p.url) == p)
        #expect(try PairingPayload(url: URL(string: p.url.absoluteString)!) == p)
    }

    @Test func hostKeyLineIsWhatKnownHostsStores() throws {
        #expect(try payload().hostKeyLine == "ssh-ed25519 \(Self.hostKey)")
    }

    @Test func refusesBadFields() {
        let ecdsa = String(String(openSSHPublicKey: NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
            .split(separator: " ")[1])
        #expect(throws: PairingError.invalidLink) { try payload(name: "") }
        #expect(throws: PairingError.invalidLink) { try payload(name: "my mac") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "not-an-ip") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "fd7a:115c:a1e0::1") }
        #expect(throws: PairingError.invalidLink) { try payload(user: "") }
        #expect(throws: PairingError.invalidLink) { try payload(user: "law liang") }
        #expect(throws: PairingError.invalidLink) { try payload(hostKey: ecdsa) }
        #expect(throws: PairingError.invalidLink) { try payload(hostKey: "garbage") }
        #expect(throws: PairingError.invalidLink) { try payload(secret: Data(repeating: 1, count: 31)) }
    }

    @Test func refusesOtherLinks() throws {
        let good = try payload().url.absoluteString
        for bad in [
            good.replacingOccurrences(of: "lostty://", with: "https://"),
            good.replacingOccurrences(of: "://pair", with: "://other"),
            good.replacingOccurrences(of: "v=1", with: "v=2"),
            "lostty://pair?v=1",
            "lostty://pair",
        ] {
            #expect(throws: PairingError.invalidLink, "\(bad)") { try PairingPayload(url: URL(string: bad)!) }
        }
    }

    @Test func newSecretsAre32RandomBytes() {
        let a = PairingPayload.newSecret()
        #expect(a.count == 32)
        #expect(a != PairingPayload.newSecret())
    }

    @Test func modelNames() {
        #expect(DeviceModel.name(forIdentifier: "iPhone14,5") == "iPhone 13")
        #expect(DeviceModel.name(forIdentifier: "iPhone17,1") == "iPhone 16 Pro")
        #expect(DeviceModel.name(forIdentifier: "iPhone99,9") == "iPhone")
        #expect(DeviceModel.name(forIdentifier: "") == "iPhone")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd macos/LosttyRemote && swift test --filter PairingPayloadTests`
Expected: compile errors (`PairingPayload`, `DeviceModel` not found).

- [ ] **Step 3: Write `PairingPayload.swift`**

```swift
import Foundation
import Network
import NIOSSH

/// What the Mac's QR code carries: the Mac's Tailscale name and address, who
/// to sign in as, the Mac's SSH host key (pinned, so the phone never trusts
/// on first use), and the one-time secret for the pairing link.
public struct PairingPayload: Equatable, Sendable {
    /// MagicDNS name, without the trailing dot.
    public var name: String
    /// Tailscale IPv4 address, for when the name doesn't resolve.
    public var ip: String
    public var user: String
    /// The Mac's ed25519 host key, standard base64 (the second field of
    /// /etc/ssh/ssh_host_ed25519_key.pub).
    public var hostKey: String
    /// 32 random bytes.
    public var secret: Data

    public init(name: String, ip: String, user: String, hostKey: String, secret: Data) throws {
        self.name = name
        self.ip = ip
        self.user = user
        self.hostKey = hostKey
        self.secret = secret
        guard isValid else { throw PairingError.invalidLink }
    }

    /// "ssh-ed25519 AAAA…", the form KnownHosts stores.
    public var hostKeyLine: String { "ssh-ed25519 \(hostKey)" }

    public static func newSecret() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "lostty"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "ip", value: ip),
            URLQueryItem(name: "user", value: user),
            URLQueryItem(name: "hostkey", value: Base64URL.encode(Data(base64Encoded: hostKey) ?? Data())),
            URLQueryItem(name: "secret", value: Base64URL.encode(secret)),
        ]
        return components.url!
    }

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "lostty", components.host == "pair"
        else { throw PairingError.invalidLink }
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] { items[item.name] = item.value }
        guard items["v"] == "1",
              let name = items["name"], let ip = items["ip"], let user = items["user"],
              let hostKey = items["hostkey"].flatMap(Base64URL.decode),
              let secret = items["secret"].flatMap(Base64URL.decode)
        else { throw PairingError.invalidLink }
        try self.init(name: name, ip: ip, user: user, hostKey: hostKey.base64EncodedString(), secret: secret)
    }

    private var isValid: Bool {
        !name.isEmpty && name.count <= 253 && !name.contains(where: \.isWhitespace)
            && IPv4Address(ip) != nil
            && !user.isEmpty && !user.contains(where: \.isWhitespace)
            && secret.count == 32
            && (try? NIOSSHPublicKey(openSSHPublicKey: hostKeyLine)) != nil
    }
}

/// base64url without padding, so the QR's URL needs no percent-escapes.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
```

`NIOSSHPublicKey(openSSHPublicKey:)` fails when the type prefix doesn't match the key blob, so an ECDSA blob labelled `ssh-ed25519` is refused.

- [ ] **Step 4: Write `DeviceModel.swift`**

```swift
import Foundation

/// A friendly name for the phone in the Mac's Allow prompt. iOS only gives
/// apps the user's own device name with a special entitlement, so Lostty
/// sends the model instead.
public enum DeviceModel {
    static let names: [String: String] = [
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
    ]

    /// "iPhone" for models not in the table.
    public static func name(forIdentifier identifier: String) -> String {
        names[identifier] ?? "iPhone"
    }

    #if os(iOS)
    /// This phone's name; the simulator reports the model it simulates.
    public static var current: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return name(forIdentifier: simulated)
        }
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return name(forIdentifier: identifier)
    }
    #endif
}
```

- [ ] **Step 5: Run the tests**

Run: `cd macos/LosttyRemote && swift test --filter PairingPayloadTests`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/Pairing/PairingPayload.swift macos/LosttyRemote/Sources/LosttyRemote/DeviceModel.swift macos/LosttyRemote/Tests/LosttyRemoteTests/PairingPayloadTests.swift
git commit -m "lostty: pairing QR payload and the phone's model name

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Editing `authorized_keys`

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/AuthorizedKeys.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/AuthorizedKeysTests.swift`

**Interfaces:**
- Produces:
  - `AuthorizedKeys.tag` (`"lostty-phone:"`); `AuthorizedKeys.Phone: Equatable, Sendable` (`id: String`, `key: String` as `"<type> <base64>"`); `line(key:id:) -> String`; `phones(in: String) -> [Phone]`; `adding(key: String, id: String, to: String) -> String?` (nil when the key is already on some line); `removing(id: String, from: String) -> String`; `removingAll(from: String) -> String`.
  - `AuthorizedKeysFile: Sendable` — `init(url: URL)`; `read() throws -> String` (empty when missing); `write(_ text: String) throws` (atomic, 0600, parent 0700, follows a symlink); on macOS `static var standard: AuthorizedKeysFile`.

- [ ] **Step 1: Write the failing tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/AuthorizedKeysTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct AuthorizedKeysTests {
    let key = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKEY1"
    let other = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKEY2"
    let theirs = """
    # my keys
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMINE me@laptop
    from="10.0.0.0/8",no-agent-forwarding ssh-rsa AAAAB3NzaRSA work\r
    """

    @Test func addsARestrictedTaggedLine() throws {
        let text = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: ""))
        #expect(text == "restrict,pty \(key) lostty-phone:a1\n")
        #expect(AuthorizedKeys.phones(in: text) == [.init(id: "a1", key: key)])
    }

    @Test func addingKeepsTheirLinesAndFixesAMissingNewline() throws {
        let text = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs))
        #expect(text == theirs + "\nrestrict,pty \(key) lostty-phone:a1\n")
    }

    @Test func aKeyAlreadyThereIsNotAddedTwice() throws {
        let once = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs))
        #expect(AuthorizedKeys.adding(key: key, id: "b2", to: once) == nil)
        #expect(AuthorizedKeys.adding(key: key, id: "b2", to: "\(key) added-by-hand\n") == nil)
    }

    @Test func removingOnePhoneLeavesEveryOtherByte() throws {
        let one = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs + "\n"))
        let two = try #require(AuthorizedKeys.adding(key: other, id: "b2", to: one))
        #expect(AuthorizedKeys.removing(id: "a1", from: two) == theirs + "\nrestrict,pty \(other) lostty-phone:b2\n")
        #expect(AuthorizedKeys.removingAll(from: two) == theirs + "\n")
        #expect(AuthorizedKeys.removing(id: "zz", from: two) == two)
    }

    @Test func onlyLinesLosttyWroteCountAsPhones() {
        let text = theirs + "\n" + "\(key) lostty-phone:hand\n" + "restrict,pty \(other) lostty-phone:\n"
        #expect(AuthorizedKeys.phones(in: text).isEmpty)
        #expect(AuthorizedKeys.removingAll(from: text) == text)
    }
}

struct AuthorizedKeysFileTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-home-\(UUID().uuidString)")

    func perms(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    @Test func createsSSHDirAndFileWithTightPermissions() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let file = AuthorizedKeysFile(url: home.appendingPathComponent(".ssh/authorized_keys"))
        #expect(try file.read() == "")
        try file.write("line\n")
        #expect(try file.read() == "line\n")
        #expect(try perms(home.appendingPathComponent(".ssh")) == 0o700)
        #expect(try perms(home.appendingPathComponent(".ssh/authorized_keys")) == 0o600)
    }

    @Test func aSymlinkStaysASymlink() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let dotfiles = home.appendingPathComponent("dotfiles")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("authorized_keys")
        try "old\n".write(to: target, atomically: true, encoding: .utf8)
        let link = ssh.appendingPathComponent("authorized_keys")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try AuthorizedKeysFile(url: link).write("new\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "new\n")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd macos/LosttyRemote && swift test --filter AuthorizedKeys`
Expected: compile errors (`AuthorizedKeys` not found).

- [ ] **Step 3: Write `AuthorizedKeys.swift`**

```swift
import Foundation

/// The phone keys Lostty adds to ~/.ssh/authorized_keys, one line each:
/// "restrict,pty <type> <base64> lostty-phone:<id>". `restrict` turns off
/// port, agent and X11 forwarding; `pty` gives the terminal back. Lines
/// Lostty didn't write are never changed, byte for byte.
public enum AuthorizedKeys {
    public static let tag = "lostty-phone:"

    public struct Phone: Equatable, Sendable {
        public var id: String
        /// "<type> <base64>"
        public var key: String

        public init(id: String, key: String) {
            self.id = id
            self.key = key
        }
    }

    public static func line(key: String, id: String) -> String {
        "restrict,pty \(key) \(tag)\(id)"
    }

    /// The phones Lostty added, in file order.
    public static func phones(in text: String) -> [Phone] {
        lines(text).compactMap(phone(in:))
    }

    /// `text` plus a line for `key`; nil when the key's base64 is already on
    /// some line (allowed before, by Lostty or by hand).
    public static func adding(key: String, id: String, to text: String) -> String? {
        let fields = key.split(separator: " ")
        guard fields.count == 2 else { return nil }
        let present = lines(text).contains { line in
            line.split(whereSeparator: \.isWhitespace).contains(fields[1])
        }
        guard !present else { return nil }
        let base = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
        return base + line(key: key, id: id) + "\n"
    }

    /// `text` without the line for phone `id`.
    public static func removing(id: String, from text: String) -> String {
        lines(text).filter { phone(in: $0)?.id != id }.joined(separator: "\n")
    }

    /// `text` without any line Lostty added.
    public static func removingAll(from text: String) -> String {
        lines(text).filter { phone(in: $0) == nil }.joined(separator: "\n")
    }

    /// A line exactly as `line(key:id:)` writes it, else nil.
    private static func phone(in line: Substring) -> Phone? {
        let fields = line.split(separator: " ")
        guard fields.count == 4, fields[0] == "restrict,pty", fields[3].hasPrefix(tag) else { return nil }
        let id = fields[3].dropFirst(tag.count)
        guard !id.isEmpty, !id.contains("\r") else { return nil }
        return Phone(id: String(id), key: "\(fields[1]) \(fields[2])")
    }

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }
}

/// Reads and atomically rewrites an authorized_keys file: a temp file in the
/// same directory, 0600, renamed over the original. A symlink (a dotfiles
/// repo) is followed, so the link itself is kept.
public struct AuthorizedKeysFile: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    #if os(macOS)
    public static var standard: AuthorizedKeysFile {
        AuthorizedKeysFile(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/authorized_keys"))
    }
    #endif

    public func read() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(_ text: String) throws {
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temp = dir.appendingPathComponent(".authorized_keys.lostty-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: temp.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temp.path, target.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? FileManager.default.removeItem(at: temp)
            throw POSIXError(code)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd macos/LosttyRemote && swift test --filter AuthorizedKeys`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/AuthorizedKeys.swift macos/LosttyRemote/Tests/LosttyRemoteTests/AuthorizedKeysTests.swift
git commit -m "lostty: add and remove paired phones in authorized_keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The phone connects to a paired Mac

Pinning from the QR, falling back from the Tailscale name to the IP, no `TERMINFO` path (the Mac copies terminfo to `~/.terminfo` in Task 5), and the spec's phone messages.

**Files:**
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift:42-55`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift:8-26,45-58,94-97`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/RemoteHostSettings.swift` (rewrite)
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift:9-50,77,88`
- Modify: `macos/Sources/Features/Remote/RemoteSurfaceIO.swift:268-283`
- Modify: `macos/Sources/Features/Remote/RemoteDebugUI.swift` (where it builds `SSHAttacher`)
- Modify: `macos/Sources/App/iOS/MobileStore.swift`, `macos/Sources/App/iOS/SettingsScreen.swift` (compile fixes only; UI comes in Task 8)
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/KnownHostsTests.swift`, `TmuxRemoteTests.swift`, `RemoteHostSettingsTests.swift` (rewrite), `HostFallbackTests.swift` (new)

**Interfaces:**
- Consumes: `PairingPayload` (Task 2).
- Produces:
  - `KnownHosts.pin(host: String, port: Int, key: String) throws` (replaces any pin).
  - `RemoteHost.terminfoDir: String?`; `TmuxRemote.attachCommand(sessionID:name:terminfoDir: String?)`.
  - `RemoteHostSettings` — `host`, `port`, `user`, `fallbackHost: String?`, `pairedAt: Date?`; `init(host:port:user:fallbackHost:pairedAt:)`; `problem`, `remoteHosts: [RemoteHost]`, `remoteHost: RemoteHost?` (first), `paired: Bool`; `static func paired(with: PairingPayload, at: Date) -> RemoteHostSettings`.
  - `RemoteConnection.connect(toFirstReachable: [RemoteHost], key:knownHosts:)`; `HostFallback.first(_:_:)`.
  - `RemoteError.notPaired`; `RemoteError.isUnreachable(_:)` public.
  - `SSHAttacher(hosts: [RemoteHost], key:knownHosts:sessionID:sessionName:)`.

- [ ] **Step 1: Write the failing tests**

Append to `KnownHostsTests.swift`:

```swift
    @Test func pinReplacesAnEarlierPin() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "ssh-ed25519 OLD")
        try hosts.pin(host: "mac", port: 22, key: "ssh-ed25519 NEW")
        #expect(KnownHosts(fileURL: file).verdict(host: "mac", port: 22, key: "ssh-ed25519 NEW") == .trusted)
        #expect(KnownHosts(fileURL: file).verdict(host: "mac", port: 22, key: "ssh-ed25519 OLD") == .changed(pinned: "ssh-ed25519 NEW"))
    }
```

Append to `TmuxRemoteTests.swift`:

```swift
    @Test func attachWithoutATerminfoPathExportsNothing() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$3", name: "proj", terminfoDir: nil)
        #expect(!cmd.contains("TERMINFO"))
        #expect(cmd.hasPrefix("[ \"$("))
        #expect(cmd.hasSuffix("attach-session -t '$3'"))
    }
```

Replace `RemoteHostSettingsTests.swift` with:

```swift
import Crypto
import Foundation
import NIOSSH
import Testing
@testable import LosttyRemote

struct RemoteHostSettingsTests {
    @Test func trimsWhatAPhoneKeyboardAdds() {
        let s = RemoteHostSettings(host: " my-mac.tail1234.ts.net ", port: 22, user: "lawliang ")
        #expect(s.problem == nil)
        #expect(s.remoteHost == RemoteHost(host: "my-mac.tail1234.ts.net", port: 22, user: "lawliang"))
    }

    @Test func incompleteSettingsSayWhatIsMissing() {
        #expect(RemoteHostSettings(host: "", port: 22, user: "me").problem == "Enter the Mac's address.")
        #expect(RemoteHostSettings(host: "mac", port: 22, user: " ").problem == "Enter your user name on the Mac.")
        #expect(RemoteHostSettings(host: "mac", port: 0, user: "me").problem == "The port must be between 1 and 65535.")
        #expect(RemoteHostSettings(host: "mac", port: 70000, user: "me").remoteHosts.isEmpty)
        #expect(RemoteHostSettings(host: "mac mini", port: 22, user: "me").problem == "The Mac's address can't contain spaces.")
    }

    @Test func theFallbackComesSecondAndOnlyWhenDifferent() {
        let s = RemoteHostSettings(host: "mac.ts.net", port: 22, user: "me", fallbackHost: "100.1.2.3")
        #expect(s.remoteHosts.map(\.host) == ["mac.ts.net", "100.1.2.3"])
        #expect(RemoteHostSettings(host: "mac", port: 22, user: "me", fallbackHost: " mac ").remoteHosts.count == 1)
        #expect(RemoteHostSettings(host: "mac", port: 22, user: "me", fallbackHost: "").remoteHosts.count == 1)
    }

    @Test func pairingFillsEverything() throws {
        let hostKey = String(String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
            .split(separator: " ")[1])
        let payload = try PairingPayload(name: "mac.ts.net", ip: "100.1.2.3", user: "law", hostKey: hostKey,
                                         secret: Data(repeating: 1, count: 32))
        let date = Date(timeIntervalSince1970: 1_000)
        let s = RemoteHostSettings.paired(with: payload, at: date)
        #expect(s == RemoteHostSettings(host: "mac.ts.net", port: 22, user: "law", fallbackHost: "100.1.2.3", pairedAt: date))
        #expect(s.paired)
        #expect(!RemoteHostSettings(host: "mac", port: 22, user: "me").paired)
    }

    @Test func savesAndLoads() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        #expect(RemoteHostSettings.load(from: defaults) == RemoteHostSettings())
        let s = RemoteHostSettings(host: "mac.ts.net", port: 2222, user: "me", fallbackHost: "100.1.2.3",
                                   pairedAt: Date(timeIntervalSince1970: 5))
        s.save(to: defaults)
        #expect(RemoteHostSettings.load(from: defaults) == s)
    }

    @Test func loadsSettingsSavedBeforePairingExisted() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        defaults.set(#"{"host":"localhost","port":22,"user":"me","terminfoDir":"/t"}"#, forKey: RemoteHostSettings.defaultsKey)
        let s = RemoteHostSettings.load(from: defaults)
        #expect(s == RemoteHostSettings(host: "localhost", port: 22, user: "me"))
        #expect(!s.paired)
    }
}
```

Create `HostFallbackTests.swift` (`Box` is the thread-safe holder from `PairingChannelTests.swift`, Task 1):

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct HostFallbackTests {
    let hosts = [RemoteHost(host: "mac.ts.net", user: "me"), RemoteHost(host: "100.1.2.3", user: "me")]
    let unreachable = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))

    @Test func anUnreachableNameFallsBackToTheAddress() async throws {
        let tried = Box<[String]>([])
        let got = try await HostFallback.first(hosts) { host in
            tried.value.append(host.host)
            if host.host == "mac.ts.net" { throw unreachable }
            return host.host
        }
        #expect(got == "100.1.2.3")
        #expect(tried.value == ["mac.ts.net", "100.1.2.3"])
    }

    @Test func aRefusedKeyOrChangedIdentityStopsAtOnce() async {
        for error in [RemoteError.keyRejected, .authenticationCancelled,
                      .hostKeyChanged(host: "mac.ts.net", pinned: "a", offered: "b")] {
            let tried = Box(0)
            await #expect(throws: error) {
                _ = try await HostFallback.first(hosts) { _ -> String in
                    tried.value += 1
                    throw error
                }
            }
            #expect(tried.value == 1)
        }
    }

    @Test func allUnreachableThrowsTheLastError() async {
        await #expect(throws: (any Error).self) {
            _ = try await HostFallback.first(hosts) { _ -> String in throw unreachable }
        }
    }

    @Test func noHostsMeansNotPaired() async {
        await #expect(throws: RemoteError.notPaired) {
            _ = try await HostFallback.first([]) { _ in "x" }
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd macos/LosttyRemote && swift test`
Expected: compile errors (`pin`, `fallbackHost`, `HostFallback`, `notPaired`, nil `terminfoDir`).

- [ ] **Step 3: `KnownHosts.pin`**

In `KnownHosts.swift`, add after `trust(host:port:key:)`, and make `trust` and `forget` write through the same helper:

```swift
    /// Pins `key` for the host, replacing any earlier pin: pairing hands the
    /// phone the Mac's key, so there is nothing to trust on first use.
    public func pin(host: String, port: Int, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var pins = load()
        pins[Self.label(host, port)] = key
        try save(pins)
    }

    private func save(_ pins: [String: String]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = pins.keys.sorted().map { "\($0) \(pins[$0]!)" }.joined(separator: "\n") + (pins.isEmpty ? "" : "\n")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
```

Replace the last three lines of `trust` (from `try FileManager.default.createDirectory` through `try text.write`) with `try save(pins)`, and the last two lines of `forget` (`let text …` and `try text.write …`) with `try save(pins)`.

- [ ] **Step 4: Optional terminfo**

In `RemoteConnection.swift`, change `RemoteHost`:

```swift
public struct RemoteHost: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var user: String
    /// A terminfo directory with xterm-ghostty to export as TERMINFO; nil
    /// when the Mac has it in ~/.terminfo (Phone Access copies it there).
    public var terminfoDir: String?

    public init(host: String, port: Int = 22, user: String, terminfoDir: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.terminfoDir = terminfoDir
    }
```

(`localhost(terminfoDir:)` is unchanged.)

In `TmuxRemote.swift`, change `attachCommand` and the end of its doc comment:

```swift
    /// The command the PTY's shell replaces itself with. `-u` and LANG keep
    /// tmux in UTF-8 when the SSH session has no locale. TERMINFO, when
    /// given, lets tmux find xterm-ghostty; otherwise ncurses finds it in
    /// ~/.terminfo. `-f /dev/null`: attach-session starts a server when
    /// none runs, and the viewer must never start one (it would read
    /// ~/.tmux.conf); a server started this way has no sessions and exits.
    ///
    /// Ids restart at $0 when the Mac's tmux server restarts, so an id alone
    /// can name a different session than the one listed: the command first
    /// checks the session's name and exits 1 if it differs.
    public static func attachCommand(sessionID: String, name: String, terminfoDir: String?) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        // TERMINFO goes first: the shell's TERM is xterm-ghostty, and the
        // guard's tmux fails on an unknown terminal without it.
        let export = terminfoDir.map { "export TERMINFO=\(shellQuote($0)); " } ?? ""
        return export + nameGuard(sessionID: sessionID, name: name)
            + "exec env LANG=\"${LANG:-en_US.UTF-8}\" \(pathPrefix) tmux -u -L lostty -f /dev/null attach-session -t \(shellQuote(sessionID))"
    }
```

- [ ] **Step 5: Rewrite `RemoteHostSettings.swift`**

```swift
import Foundation

/// The Mac the phone connects to: filled in by pairing, or typed under
/// Advanced. Stored in UserDefaults as JSON under `defaultsKey`; a JSON
/// string is accepted too, so a launch argument (`-LosttyRemoteHost
/// '{"host":…}'`) can set it. Settings saved by older builds (with a
/// terminfoDir) still load.
public struct RemoteHostSettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "LosttyRemoteHost"

    public var host: String
    public var port: Int
    public var user: String
    /// The Mac's Tailscale address, tried when `host` (its name) can't be reached.
    public var fallbackHost: String?
    /// When this phone was paired with the Mac; nil for typed settings.
    public var pairedAt: Date?

    public init(host: String = "", port: Int = 22, user: String = "", fallbackHost: String? = nil, pairedAt: Date? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.fallbackHost = fallbackHost
        self.pairedAt = pairedAt
    }

    /// The settings pairing with `payload` produces.
    public static func paired(with payload: PairingPayload, at date: Date) -> RemoteHostSettings {
        RemoteHostSettings(host: payload.name, port: 22, user: payload.user, fallbackHost: payload.ip, pairedAt: date)
    }

    public var paired: Bool { pairedAt != nil }

    /// What to fix before connecting, or nil.
    public var problem: String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Enter the Mac's address." }
        if host.contains(where: \.isWhitespace) { return "The Mac's address can't contain spaces." }
        if user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your user name on the Mac." }
        if !(1...65535).contains(port) { return "The port must be between 1 and 65535." }
        return nil
    }

    /// The Mac's name, then its address; empty while `problem` is set.
    public var remoteHosts: [RemoteHost] {
        guard problem == nil else { return [] }
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var hosts = [RemoteHost(host: primary, port: port, user: user)]
        if let fallback = fallbackHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty, fallback != primary, !fallback.contains(where: \.isWhitespace) {
            hosts.append(RemoteHost(host: fallback, port: port, user: user))
        }
        return hosts
    }

    public var remoteHost: RemoteHost? { remoteHosts.first }

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

- [ ] **Step 6: Host fallback and errors**

In `RemoteConnection.swift`, add inside `RemoteConnection` after `connect(to:key:knownHosts:)`:

```swift
    /// Connects to the first host that answers: the Mac's Tailscale name,
    /// then its address. Only "couldn't reach" moves on; a refused key, a
    /// changed host key or a cancelled Face ID stop at once.
    public static func connect(toFirstReachable hosts: [RemoteHost], key: RemoteKey, knownHosts: KnownHosts) async throws -> RemoteConnection {
        try await HostFallback.first(hosts) { try await connect(to: $0, key: key, knownHosts: knownHosts) }
    }
```

and at the end of the file:

```swift
enum HostFallback {
    static func first<T>(_ hosts: [RemoteHost], _ connect: (RemoteHost) async throws -> T) async throws -> T {
        var last: Error = RemoteError.notPaired
        for host in hosts {
            do {
                return try await connect(host)
            } catch let error where RemoteError.isUnreachable(error) {
                last = error
            }
        }
        throw last
    }
}
```

In `RemoteKey.swift`:
- add `case notPaired` to `RemoteError` (after `tmuxMissing`), with message `"Pair this iPhone with your Mac first."` in `message`;
- change `private static func isUnreachable` to `public static func isUnreachable`;
- replace the `hostKeyChanged` case with a call, and the iOS/macOS constants so iOS shows the spec's text:

```swift
        case .hostKeyChanged(let host, let pinned, _):
            Self.hostKeyChangedMessage(host: host, pinned: pinned)
```

```swift
    #if os(iOS)
    private static func hostKeyChangedMessage(host: String, pinned: String) -> String {
        "This Mac's identity changed. If you reinstalled macOS, pair again; otherwise, don't connect."
    }
    private static let keyRejectedMessage = "Your Mac doesn't accept this phone anymore."
    private static let authCancelledMessage =
        "Face ID was cancelled, so Lostty did not connect. Open the session again to retry."
    #else
    private static func hostKeyChangedMessage(host: String, pinned: String) -> String {
        "The SSH host key for \(host) changed since it was first trusted (pinned \(pinned.prefix(40))…). "
            + "Lostty will not connect. "
            + hostKeyChangedAdvice
    }
    private static let hostKeyChangedAdvice =
        "If the Mac's key really changed, remove its line from known_hosts in Application Support/Lostty."
    private static let keyRejectedMessage =
        "The Mac refused Lostty's key. Add the line from \"Copy Remote Key\" to ~/.ssh/authorized_keys."
    private static let authCancelledMessage =
        "Touch ID was cancelled, so Lostty did not connect. Open the session again to retry."
    #endif
```

- in `describe(_:host:)`, make the unreachable text platform-specific:

```swift
        if isUnreachable(error) {
            #if os(iOS)
            return "Can't reach your Mac. Is Tailscale on here and on the Mac, and is the Mac awake?"
            #else
            return "Couldn't reach the Mac at \(host.host):\(host.port). "
                + "Check the address, and that Tailscale and Remote Login are on."
            #endif
        }
```

- [ ] **Step 7: Callers**

`RemoteSurfaceIO.swift`, `SSHAttacher`: replace `let host: RemoteHost` with `let hosts: [RemoteHost]` and the connect line with
`let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try await key(), knownHosts: knownHosts)`.

`RemoteDebugUI.swift:74-76`: `SSHAttacher(hosts: [host], key: { key }, knownHosts: knownHosts, sessionID: session.id, sessionName: session.name)`.

`MobileStore.swift` (compile fixes; Task 8 builds on these):
- `describe(_:)`: `guard let host = settings.remoteHost` stays.
- `forgetHostKey()`: forget every host:

```swift
    func forgetHostKey() {
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return
        }
        do {
            for host in hosts { try knownHosts.forget(host: host.host, port: host.port) }
            message = "Forgot the Mac's host key. The next connection will trust the key it offers."
        } catch {
            message = error.localizedDescription
        }
    }
```

- `terminalClosedItself`: message becomes `"Couldn't open \(session.name). Check that tmux runs on the Mac."`.
- `refresh()`, `kill(_:)`: replace `guard let host = settings.remoteHost` with `let hosts = settings.remoteHosts; guard !hosts.isEmpty` (refresh sets `message = settings.problem` in the else), and `RemoteConnection.connect(to: host, …)` with `RemoteConnection.connect(toFirstReachable: hosts, …)`.
- `terminal(for:app:)`: same guard, and `SSHAttacher(hosts: hosts, …)`.

`SettingsScreen.swift`: delete the `TextField("Lostty terminfo on the Mac", …)` and its four modifier lines.

- [ ] **Step 8: Run all package tests and both builds**

Run: `cd macos/LosttyRemote && swift test`
Expected: all pass, including the new ones. The old `attachExportsTerminfoBeforeTheGuard`-style tests still pass (they pass a non-nil path).

Run the iOS build check and `macos/build.nu --configuration Debug --action build` (Global Constraints).
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift macos/LosttyRemote/Sources/LosttyRemote/RemoteHostSettings.swift macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift macos/LosttyRemote/Tests/LosttyRemoteTests/KnownHostsTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteHostSettingsTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/HostFallbackTests.swift macos/Sources/Features/Remote/RemoteSurfaceIO.swift macos/Sources/Features/Remote/RemoteDebugUI.swift macos/Sources/App/iOS/MobileStore.swift macos/Sources/App/iOS/SettingsScreen.swift
git commit -m "lostty: phone pins the Mac from pairing, falls back to its address, needs no terminfo path

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Mac checks that need no admin, and terminfo

**Files:**
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift`
- Test: `macos/Tests/PhoneAccess/PhoneAccessChecksTests.swift`

**Interfaces:**
- Consumes: `TmuxClient.locate()` (existing, `Sources/Features/Sessions/TmuxClient.swift`).
- Produces:
  - `PhoneAccessStatus: Equatable` — `tailscale: Tailscale?` (`running: Bool`, `name: String?`, `ipv4: String?`), `tmuxPath: String?`, `remoteLogin: Bool`, `authMethods: [String]?`, `lockdownFileExists: Bool`, `blockAllIncoming: Bool`, `terminfoInstalled: Bool`; `tailscaleReady`, `passwordsOff`, `readyToPair(lockdownSkipped:) -> Bool`.
  - `PhoneAccessParse.tailscale(statusJSON:)`, `.sshdEnabled(printDisabled:)`, `.authMethods(sshOutput:)`, `.blockAll(firewallOutput:)`.
  - `Command.run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> Command.Result?` (`status: Int32`, `output: String`).
  - `PhoneAccessTerminfo.entries`, `.installed(bundle: URL, home: URL) -> Bool`, `.install(bundle: URL, home: URL) throws` (`home` is the `~/.terminfo` directory).
  - `PhoneAccessProbe.lockdownPath` (`"/etc/ssh/sshd_config.d/000-lostty.conf"`), `PhoneAccessProbe.run() -> PhoneAccessStatus`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/PhoneAccess/PhoneAccessChecksTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct PhoneAccessChecksTests {
    @Test func readsTailscaleStatus() {
        let json = #"{"BackendState":"Running","Self":{"DNSName":"laws-mbp.tail278d1f.ts.net.","TailscaleIPs":["fd7a:115c:a1e0::1","100.126.63.10"]}}"#
        #expect(PhoneAccessParse.tailscale(statusJSON: Data(json.utf8))
            == .init(running: true, name: "laws-mbp.tail278d1f.ts.net", ipv4: "100.126.63.10"))
        let out = #"{"BackendState":"NeedsLogin","Self":{"DNSName":"","TailscaleIPs":[]}}"#
        #expect(PhoneAccessParse.tailscale(statusJSON: Data(out.utf8)) == .init(running: false, name: nil, ipv4: nil))
        #expect(PhoneAccessParse.tailscale(statusJSON: Data("not json".utf8)) == nil)
    }

    @Test func readsWhetherRemoteLoginIsEnabled() {
        let on = "disabled services = {\n\t\t\"com.apple.foo\" => disabled\n\t\t\"com.openssh.sshd\" => enabled\n}"
        let off = "disabled services = {\n\t\t\"com.openssh.sshd\" => disabled\n}"
        #expect(PhoneAccessParse.sshdEnabled(printDisabled: on))
        #expect(!PhoneAccessParse.sshdEnabled(printDisabled: off))
        #expect(!PhoneAccessParse.sshdEnabled(printDisabled: ""))
    }

    @Test func readsTheLoginMethodsSSHOffers() {
        #expect(PhoneAccessParse.authMethods(sshOutput: "me@127.0.0.1: Permission denied (publickey).\r\n") == ["publickey"])
        #expect(PhoneAccessParse.authMethods(sshOutput: "me@127.0.0.1: Permission denied (publickey,password,keyboard-interactive).")
            == ["publickey", "password", "keyboard-interactive"])
        #expect(PhoneAccessParse.authMethods(sshOutput: "ssh: connect to host 127.0.0.1 port 22: Connection refused") == nil)
    }

    @Test func passwordStillOfferedIsNotLockedDown() {
        var status = Self.ready
        status.authMethods = ["publickey", "password"]
        #expect(!status.passwordsOff)
        status.authMethods = ["publickey", "keyboard-interactive"]
        #expect(!status.passwordsOff)
        #expect(!status.readyToPair(lockdownSkipped: false))
        #expect(status.readyToPair(lockdownSkipped: true))
    }

    @Test func readsTheFirewallsBlockAll() {
        #expect(PhoneAccessParse.blockAll(firewallOutput: "Firewall has block all state set to enabled."))
        #expect(!PhoneAccessParse.blockAll(firewallOutput: "Firewall has block all state set to disabled."))
        #expect(!PhoneAccessParse.blockAll(firewallOutput: ""))
    }

    static let ready = PhoneAccessStatus(
        tailscale: .init(running: true, name: "mac.ts.net", ipv4: "100.1.2.3"),
        tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
        lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true)

    @Test func everyRowMustBeDoneToPair() {
        #expect(Self.ready.readyToPair(lockdownSkipped: false))
        var s = Self.ready
        s.tailscale = .init(running: true, name: nil, ipv4: "100.1.2.3")
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.tmuxPath = nil
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.remoteLogin = false
        #expect(!s.readyToPair(lockdownSkipped: true))
        s = Self.ready; s.blockAllIncoming = true
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.terminfoInstalled = false
        #expect(!s.readyToPair(lockdownSkipped: false))
    }

    @Test func installsTerminfoAndNoticesWhenItMatches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-ti-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("bundle")
        let home = root.appendingPathComponent("home/.terminfo")
        for entry in PhoneAccessTerminfo.entries {
            let file = bundle.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(entry.utf8).write(to: file)
        }
        #expect(!PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try PhoneAccessTerminfo.install(bundle: bundle, home: home)
        #expect(PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try Data("older".utf8).write(to: home.appendingPathComponent(PhoneAccessTerminfo.entries[0]))
        #expect(!PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try PhoneAccessTerminfo.install(bundle: bundle, home: home)
        #expect(PhoneAccessTerminfo.installed(bundle: bundle, home: home))
    }

    @Test func commandsReturnOutputAndGiveUpOnHangs() {
        let echo = Command.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(echo?.status == 3)
        #expect(echo?.output.contains("out") == true)
        #expect(echo?.output.contains("err") == true)
        let start = Date()
        #expect(Command.run("/bin/sleep", ["10"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(Command.run("/nonexistent/tool", []) == nil)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh PhoneAccessChecksTests`
Expected: build fails (`PhoneAccessParse` etc. not found).

- [ ] **Step 3: Write `PhoneAccessChecks.swift`**

```swift
#if os(macOS)
import Foundation

/// What Phone Access needs from this Mac, all read without admin rights.
struct PhoneAccessStatus: Equatable {
    struct Tailscale: Equatable {
        var running: Bool
        /// MagicDNS name, without the trailing dot.
        var name: String?
        var ipv4: String?
    }

    /// nil: Tailscale isn't installed.
    var tailscale: Tailscale?
    var tmuxPath: String?
    var remoteLogin: Bool
    /// The login methods sshd offers before any are tried; nil when sshd
    /// didn't answer.
    var authMethods: [String]?
    var lockdownFileExists: Bool
    var blockAllIncoming: Bool
    var terminfoInstalled: Bool

    var tailscaleReady: Bool {
        tailscale?.running == true && tailscale?.name != nil && tailscale?.ipv4 != nil
    }

    /// Only keys can sign in. Read from what sshd offers, so a customer
    /// setting that overrides Lostty's file shows up here.
    var passwordsOff: Bool { authMethods.map(Set.init) == ["publickey"] }

    func readyToPair(lockdownSkipped: Bool) -> Bool {
        tailscaleReady && tmuxPath != nil && remoteLogin && (passwordsOff || lockdownSkipped)
            && !blockAllIncoming && terminfoInstalled
    }
}

enum PhoneAccessParse {
    /// `tailscale status --json`; nil when it isn't JSON.
    static func tailscale(statusJSON: Data) -> PhoneAccessStatus.Tailscale? {
        guard let root = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any] else { return nil }
        let me = root["Self"] as? [String: Any]
        let dns = (me?["DNSName"] as? String).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        let ips = me?["TailscaleIPs"] as? [String] ?? []
        return .init(
            running: root["BackendState"] as? String == "Running",
            name: dns?.isEmpty == false ? dns : nil,
            ipv4: ips.first { !$0.contains(":") })
    }

    /// `launchctl print-disabled system` lists sshd as enabled.
    static func sshdEnabled(printDisabled: String) -> Bool {
        printDisabled.split(separator: "\n").contains { line in
            line.contains("\"com.openssh.sshd\"") && line.contains("=> enabled")
        }
    }

    /// The list in "Permission denied (publickey,password)."; nil when ssh
    /// never got that far.
    static func authMethods(sshOutput: String) -> [String]? {
        guard let open = sshOutput.range(of: "Permission denied ("),
              let close = sshOutput[open.upperBound...].firstIndex(of: ")")
        else { return nil }
        return sshOutput[open.upperBound..<close].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// `socketfilterfw --getblockall` says block-all is on.
    static func blockAll(firewallOutput: String) -> Bool {
        let text = firewallOutput.lowercased()
        return !text.contains("disabled") && text.range(of: #"\benabled\b"#, options: .regularExpression) != nil
    }
}

/// Runs a program; its exit status and combined stdout and stderr. nil when
/// it couldn't start, or ran past `timeout` (then it is killed).
enum Command {
    struct Result: Equatable {
        var status: Int32
        var output: String
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Read while it runs: a full pipe would block the child.
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            collected.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        drained.wait()
        return Result(status: process.terminationStatus, output: String(decoding: collected.data, as: UTF8.self))
    }
}

/// xterm-ghostty in ~/.terminfo, where ncurses looks by default, so the
/// phone's attach doesn't depend on where Lostty.app is.
enum PhoneAccessTerminfo {
    static let entries = ["78/xterm-ghostty", "67/ghostty"]

    static func installed(bundle: URL, home: URL) -> Bool {
        entries.allSatisfy { entry in
            FileManager.default.contentsEqual(
                atPath: bundle.appendingPathComponent(entry).path,
                andPath: home.appendingPathComponent(entry).path)
        }
    }

    static func install(bundle: URL, home: URL) throws {
        for entry in entries {
            let target = home.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: bundle.appendingPathComponent(entry)).write(to: target, options: .atomic)
        }
    }

    static var bundleDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("terminfo") }
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".terminfo")
    }
}

enum PhoneAccessProbe {
    static let tailscaleCLI = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static let lockdownPath = "/etc/ssh/sshd_config.d/000-lostty.conf"

    /// Runs every check. Takes up to a few seconds: call it off the main thread.
    static func run() -> PhoneAccessStatus {
        var tailscale: PhoneAccessStatus.Tailscale?
        if FileManager.default.isExecutableFile(atPath: tailscaleCLI) {
            let out = Command.run(tailscaleCLI, ["status", "--json"])?.output ?? ""
            tailscale = PhoneAccessParse.tailscale(statusJSON: Data(out.utf8))
                ?? .init(running: false, name: nil, ipv4: nil)
        }
        let enabled = PhoneAccessParse.sshdEnabled(
            printDisabled: Command.run("/bin/launchctl", ["print-disabled", "system"])?.output ?? "")
        // "none" never authenticates, so sshd answers with the methods it
        // offers. -F /dev/null ignores the user's ssh config.
        let ssh = Command.run("/usr/bin/ssh", [
            "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "PreferredAuthentications=none",
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=3", "-o", "LogLevel=ERROR", "\(NSUserName())@127.0.0.1", "true",
        ])
        let methods = PhoneAccessParse.authMethods(sshOutput: ssh?.output ?? "")
        let firewall = Command.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getblockall"])?.output ?? ""
        return PhoneAccessStatus(
            tailscale: tailscale,
            tmuxPath: TmuxClient.locate(),
            remoteLogin: enabled && methods != nil,
            authMethods: methods,
            lockdownFileExists: FileManager.default.fileExists(atPath: lockdownPath),
            blockAllIncoming: PhoneAccessParse.blockAll(firewallOutput: firewall),
            terminfoInstalled: PhoneAccessTerminfo.installed(
                bundle: PhoneAccessTerminfo.bundleDirectory, home: PhoneAccessTerminfo.homeDirectory))
    }
}
#endif
```

- [ ] **Step 4: Run the tests**

Run: `macos/skins-test.sh PhoneAccessChecksTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift macos/Tests/PhoneAccess/PhoneAccessChecksTests.swift
git commit -m "lostty: Phone Access checks that need no admin, and terminfo in ~/.terminfo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The one admin prompt

**Files:**
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessAdmin.swift`
- Test: `macos/Tests/PhoneAccess/PhoneAccessAdminTests.swift`

**Interfaces:**
- Consumes: `PhoneAccessProbe.lockdownPath` (Task 5).
- Produces: `PhoneAccessAdmin.setupScript(enableRemoteLogin: Bool, lockPasswords: Bool) -> String?`; `PhoneAccessAdmin.unlockScript: String`; `PhoneAccessAdmin.appleScript(running: String, prompt: String) -> String`; `PhoneAccessAdmin.Outcome` (`.done`, `.cancelled`, `.failed(String)`); `@MainActor PhoneAccessAdmin.run(_ script: String, prompt: String) -> Outcome`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/PhoneAccess/PhoneAccessAdminTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh PhoneAccessAdminTests`
Expected: build fails (`PhoneAccessAdmin` not found).

- [ ] **Step 3: Write `PhoneAccessAdmin.swift`**

```swift
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

    /// Turns password logins back on (Turn Off Phone Access).
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
```

- [ ] **Step 4: Run the tests**

Run: `macos/skins-test.sh PhoneAccessAdminTests`
Expected: `** TEST SUCCEEDED **`. Do not call `PhoneAccessAdmin.run` from tests or by hand: it changes the real system (Task 9 desk check).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/PhoneAccess/PhoneAccessAdmin.swift macos/Tests/PhoneAccess/PhoneAccessAdminTests.swift
git commit -m "lostty: one admin prompt turns on Remote Login and turns off password logins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The Phone Access window on the Mac

**Files:**
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift`
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift`
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift`
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessUI.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift:342` (after `ClaudeHooksUI.installMenuItem`)
- Modify: `macos/Ghostty-Info.plist` (add `NSBonjourServices`)
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj` (the three macOS `INFOPLIST_KEY_NSLocalNetworkUsageDescription` lines)
- Test: `macos/Tests/PhoneAccess/PhoneAccessModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3, 5, 6.
- Produces:
  - `PhoneAccessRow: Identifiable, Equatable` — `id: Kind` (`.tailscale, .tmux, .remoteLogin, .passwords, .firewall, .terminfo`), `title`, `detail`, `state: State` (`.ok, .warning, .missing`), `fixes: [Fix]` (`.installTailscale, .openTailscale, .copyBrew, .adminSetup, .lockPasswords, .skipLockdown, .openFirewall, .installTerminfo`); `static func rows(for: PhoneAccessStatus, lockdownSkipped: Bool) -> [PhoneAccessRow]`.
  - `PhoneAccessNames` — `init(defaults: UserDefaults)`, `entries() -> [String: Entry]`, `set(_ id: String, _ entry: Entry?)`; `Entry: Codable, Equatable` (`name`, `paired: Date`); `static func phones(keysText: String, names: [String: Entry]) -> [PairedPhone]`.
  - `PairedPhone: Identifiable, Equatable` — `id`, `name`, `paired: Date?`.
  - `PhoneAccessHostKey.base64(fromPub: String) -> String?`.
  - `PhoneAccessStore` (`@MainActor ObservableObject`), `PhoneAccessView`, `PhoneAccessUI.installMenuItem(after:)`.

- [ ] **Step 1: Write the failing model tests**

`macos/Tests/PhoneAccess/PhoneAccessModelTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

struct PhoneAccessRowsTests {
    let ready = PhoneAccessStatus(
        tailscale: .init(running: true, name: "mac.ts.net", ipv4: "100.1.2.3"),
        tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
        lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true)

    func row(_ kind: PhoneAccessRow.Kind, _ status: PhoneAccessStatus, skipped: Bool = false) -> PhoneAccessRow {
        PhoneAccessRow.rows(for: status, lockdownSkipped: skipped).first { $0.id == kind }!
    }

    @Test func allDoneIsAllOK() {
        let rows = PhoneAccessRow.rows(for: ready, lockdownSkipped: false)
        #expect(rows.map(\.id) == [.tailscale, .tmux, .remoteLogin, .passwords, .firewall, .terminfo])
        #expect(rows.allSatisfy { $0.state == .ok })
    }

    @Test func tailscaleMissingOrSignedOut() {
        var s = ready
        s.tailscale = nil
        #expect(row(.tailscale, s).fixes == [.installTailscale])
        s.tailscale = .init(running: false, name: nil, ipv4: nil)
        #expect(row(.tailscale, s).fixes == [.openTailscale])
        #expect(row(.tailscale, s).state == .missing)
    }

    @Test func passwordsOnOffersSetUpOrSkip() {
        var s = ready
        s.authMethods = ["publickey", "password"]
        s.lockdownFileExists = false
        #expect(row(.passwords, s).state == .missing)
        #expect(row(.passwords, s).fixes == [.lockPasswords, .skipLockdown])
        let skipped = row(.passwords, s, skipped: true)
        #expect(skipped.state == .warning)
        #expect(skipped.detail == "Without this, anyone who can reach this Mac can try your password over SSH, on any network, for every account on this Mac. If you SSH into this Mac with a password from elsewhere, that keeps working.")
        #expect(skipped.fixes == [.lockPasswords])
    }

    @Test func lockdownFileButPasswordsStillOn() {
        var s = ready
        s.authMethods = ["publickey", "password"]
        let r = row(.passwords, s)
        #expect(r.state == .missing)
        #expect(r.fixes.isEmpty)
        #expect(r.detail.contains("/etc/ssh/sshd_config"))
    }

    @Test func remoteLoginOffNeedsTheAdminStep() {
        var s = ready
        s.remoteLogin = false
        s.authMethods = nil
        #expect(row(.remoteLogin, s).fixes == [.adminSetup])
        #expect(row(.passwords, s).state == .missing)
        #expect(row(.passwords, s).fixes.isEmpty)
    }

    @Test func otherRowsHaveTheirFixes() {
        var s = ready
        s.tmuxPath = nil
        s.blockAllIncoming = true
        s.terminfoInstalled = false
        #expect(row(.tmux, s).fixes == [.copyBrew])
        #expect(row(.firewall, s).fixes == [.openFirewall])
        #expect(row(.terminfo, s).fixes == [.installTerminfo])
    }
}

struct PhoneAccessNamesTests {
    @Test func storesNamesAndMergesThemWithTheKeysFile() {
        let names = PhoneAccessNames(defaults: UserDefaults(suiteName: "lostty-phones-\(UUID().uuidString)")!)
        let date = Date(timeIntervalSince1970: 100)
        names.set("a1", .init(name: "iPhone 13", paired: date))
        let keys = """
        ssh-ed25519 AAAA mine
        restrict,pty ecdsa-sha2-nistp256 AAAAKEY1 lostty-phone:a1
        restrict,pty ecdsa-sha2-nistp256 AAAAKEY2 lostty-phone:b2

        """
        #expect(PhoneAccessNames.phones(keysText: keys, names: names.entries()) == [
            PairedPhone(id: "a1", name: "iPhone 13", paired: date),
            PairedPhone(id: "b2", name: "iPhone", paired: nil),
        ])
        names.set("a1", nil)
        #expect(names.entries().isEmpty)
    }

    @Test func readsTheMacsHostKey() {
        #expect(PhoneAccessHostKey.base64(fromPub: "ssh-ed25519 AAAAC3NzaKEY root@mac\n") == "AAAAC3NzaKEY")
        #expect(PhoneAccessHostKey.base64(fromPub: "ecdsa-sha2-nistp256 AAAA root@mac") == nil)
        #expect(PhoneAccessHostKey.base64(fromPub: "") == nil)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh PhoneAccessRowsTests`
Expected: build fails (`PhoneAccessRow` not found).

- [ ] **Step 3: Write `PhoneAccessModel.swift`**

```swift
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
```

- [ ] **Step 4: Run the model tests**

Run: `macos/skins-test.sh PhoneAccessRowsTests` then `macos/skins-test.sh PhoneAccessNamesTests`
Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 5: Write `PhoneAccessStore.swift`**

```swift
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
                decide: { [weak self] request in await self?.ask(request) ?? false },
                onFinish: { [weak self] allowed in
                    Task { @MainActor in self?.pairingFinished(id, allowed: allowed) }
                })
            stopPairing()
            self.server = server
            pairingID = id
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
    private func ask(_ request: PairingRequest) async -> Bool {
        guard let key = request.acceptedKey else { return false }
        let model = request.displayModel
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow “\(model)” to open your Lostty sessions?"
        alert.informativeText = "It can open and type in every Lostty session on this Mac. You can remove it later in Phone Access."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            let id = UUID().uuidString.lowercased()
            let text = try keysFile.read()
            if let updated = AuthorizedKeys.adding(key: key, id: id, to: text) {
                try keysFile.write(updated)
                names.set(id, .init(name: model, paired: Date()))
            }
            return true
        } catch {
            message = "Couldn't add the phone to ~/.ssh/authorized_keys: \(error.localizedDescription)"
            return false
        }
    }

    private func pairingFinished(_ id: UUID, allowed: Bool) {
        guard pairingID == id else { return }
        server = nil
        pairing = nil
        message = allowed ? "Paired. Finish on your phone." : "Pairing was declined."
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
```

- [ ] **Step 6: Write `PhoneAccessView.swift`**

```swift
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
        }
    }
}

private struct PairingSheetItem: Identifiable {
    var pairing: PhoneAccessStore.Pairing
    var id: String {
        switch pairing {
        case .showing(let payload, _): payload.url.absoluteString
        case .expired: "expired"
        }
    }
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
```

`PhoneAccessStore.Pairing: Equatable` relies on `PairingPayload` being `Equatable` (it is). The window re-checks each time it becomes key (`PhoneAccessUI`, Step 7), including when it first opens.

- [ ] **Step 7: Write `PhoneAccessUI.swift` and install the menu item**

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// "Phone Access…" in the app menu, and its window.
@MainActor
enum PhoneAccessUI {
    private static var window: NSWindow?
    private static let store = PhoneAccessStore()

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Phone Access…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: PhoneAccessView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Phone Access"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            // Re-check when the customer comes back from a fix (Terminal,
            // System Settings, Tailscale); only this window, so switching
            // terminal windows doesn't run the checks.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    if !store.checking && store.pairing == nil { store.refresh() }
                }
            }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { PhoneAccessUI.show() }
    }
}
#endif
```

In `AppDelegate.swift`, right after `ClaudeHooksUI.installMenuItem(after: menuOpenConfig)`:

```swift
        // Lostty Mobile: pair a phone and check this Mac's setup for it.
        PhoneAccessUI.installMenuItem(after: menuOpenConfig)
```

- [ ] **Step 8: Bonjour service and local network text on the Mac**

In `macos/Ghostty-Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>NSBonjourServices</key>
	<array>
		<string>_lostty-pair._tcp</string>
	</array>
```

In `macos/Ghostty.xcodeproj/project.pbxproj`, change each of the three macOS lines `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "A program running within Ghostty would like to access the local network.";` to:

```
INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Lostty uses the local network to pair your iPhone. Programs running in Lostty may use it too.";
```

- [ ] **Step 9: Build and run all Phone Access tests**

Run: `macos/build.nu --configuration Debug --action build`
Expected: `** BUILD SUCCEEDED **`.
Run: `macos/skins-test.sh PhoneAccessRowsTests`, `macos/skins-test.sh PhoneAccessNamesTests`, `macos/skins-test.sh PhoneAccessChecksTests`, `macos/skins-test.sh PhoneAccessAdminTests`
Expected: each `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/Features/PhoneAccess macos/Tests/PhoneAccess/PhoneAccessModelTests.swift macos/Sources/App/macOS/AppDelegate.swift macos/Ghostty-Info.plist macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "lostty: Phone Access window: checklist, pairing QR, Allow, paired phones

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Pairing on the phone

**Files:**
- Create: `macos/Lostty-iOS-Info.plist`
- Create: `macos/Sources/App/iOS/QRScannerView.swift`
- Create: `macos/Sources/App/iOS/PairingScreen.swift`
- Create: `macos/Sources/App/iOS/WelcomeScreen.swift`
- Modify: `macos/Sources/App/iOS/MobileStore.swift`
- Modify: `macos/Sources/App/iOS/SessionsScreen.swift`
- Modify: `macos/Sources/App/iOS/SettingsScreen.swift` (rewrite)
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj` (the two Ghostty-iOS build configurations)

**Interfaces:**
- Consumes: Tasks 1, 2, 4.
- Produces: `MobileStore.PairingPhase` (`.idle, .finding, .waitingForAllow, .testing, .failed(String, canRetryTest: Bool), .done`); `MobileStore.pairing`, `needsPairing`, `pair(link: String) async`, `retryPairingTest() async`, `resetPairing()`; `MobileStore.noSessionsMessage`.

- [ ] **Step 1: iOS Info.plist, camera and local network text**

`macos/Lostty-iOS-Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSBonjourServices</key>
	<array>
		<string>_lostty-pair._tcp</string>
	</array>
</dict>
</plist>
```

In `project.pbxproj`, in both Ghostty-iOS configurations (the ones with `PRODUCT_BUNDLE_IDENTIFIER = "com.lawliang.lostty-mobile";`), next to `INFOPLIST_KEY_NSFaceIDUsageDescription`, add:

```
				INFOPLIST_FILE = "Lostty-iOS-Info.plist";
				INFOPLIST_KEY_NSCameraUsageDescription = "Lostty uses the camera to scan the pairing code on your Mac.";
				INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Lostty finds your Mac nearby while you pair them.";
```

(`GENERATE_INFOPLIST_FILE = YES` stays: Xcode merges the file with the generated keys.)

- [ ] **Step 2: Pairing in `MobileStore`**

Add to `MobileStore` (inside the class, before `// MARK: Reconnect triggers`):

```swift
    // MARK: Pairing

    enum PairingPhase: Equatable {
        case idle
        case finding
        case waitingForAllow
        case testing
        case failed(String, canRetryTest: Bool)
        case done
    }

    @Published private(set) var pairing: PairingPhase = .idle
    /// The Mac refused this phone or its identity changed: show Pair Again.
    @Published private(set) var needsPairing = false
    /// Kept after the Mac allowed this phone, so a failed test can retry
    /// without scanning again.
    private var allowedPayload: PairingPayload?

    static let noSessionsMessage = "No sessions. Is Lostty open on your Mac?"
    static let tailscaleHint = "Is Tailscale on and signed into the same account as your Mac?"

    func resetPairing() {
        pairing = .idle
        allowedPayload = nil
    }

    /// Scan → find the Mac nearby → send this phone's key → wait for Allow
    /// → test over Tailscale. Only a working test saves the pairing.
    func pair(link: String) async {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let payload = try? PairingPayload(url: url)
        else {
            pairing = .failed(PairingError.invalidLink.message, canRetryTest: false)
            return
        }
        do {
            let key = try remoteKey()
            pairing = .finding
            let endpoint = try await PairingClient.find(secret: payload.secret)
            pairing = .waitingForAllow
            let response = try await PairingClient.send(
                PairingRequest(publicKey: key.publicKeyLine, model: DeviceModel.current),
                to: endpoint, secret: payload.secret)
            guard response.result == .allowed else {
                pairing = .failed("Your Mac declined. Try again from Phone Access.", canRetryTest: false)
                return
            }
            allowedPayload = payload
        } catch let error as PairingError {
            pairing = .failed(error.message, canRetryTest: false)
            return
        } catch {
            pairing = .failed(describe(error), canRetryTest: false)
            return
        }
        await retryPairingTest()
    }

    /// Pins the Mac's key from the QR and connects over Tailscale.
    func retryPairingTest() async {
        guard let payload = allowedPayload else { return }
        pairing = .testing
        let candidate = RemoteHostSettings.paired(with: payload, at: Date())
        do {
            for host in candidate.remoteHosts {
                try knownHosts.pin(host: host.host, port: host.port, key: payload.hostKeyLine)
            }
            let connection = try await RemoteConnection.connect(
                toFirstReachable: candidate.remoteHosts, key: try remoteKey(), knownHosts: knownHosts)
            let found = try await connection.sessions()
            await connection.close()
            settings = candidate
            saveSettings()
            sessions = RemoteSession.forPicking(found)
            message = sessions.isEmpty ? Self.noSessionsMessage : nil
            needsPairing = false
            allowedPayload = nil
            pairing = .done
        } catch {
            let text = RemoteError.isUnreachable(error)
                ? "Your Mac allowed this phone, but Lostty couldn't reach it. \(Self.tailscaleHint)"
                : describe(error)
            pairing = .failed(text, canRetryTest: true)
        }
    }

    /// Errors that only pairing again fixes.
    private func noteNeedsPairing(_ error: Error) {
        switch error as? RemoteError {
        case .keyRejected?, .hostKeyChanged?: needsPairing = true
        default: break
        }
    }
```

In `refresh()`, change the empty-list message and note errors:

```swift
            message = sessions.isEmpty ? Self.noSessionsMessage : nil
            needsPairing = false
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
        }
```

In `kill(_:)`'s `catch`, add `noteNeedsPairing(error)` after setting `message`.

- [ ] **Step 3: Write `QRScannerView.swift`**

```swift
#if os(iOS)
import SwiftUI
import VisionKit

/// The camera, looking for one QR code; reports its text once.
struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    /// The hardware can scan. `DataScannerViewController.isAvailable` is
    /// also false until camera access is granted, so the screen asks first.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFound: (String) -> Void
        private var reported = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !reported else { return }
            for item in added {
                if case .barcode(let code) = item, let text = code.payloadStringValue, text.hasPrefix("lostty://pair") {
                    reported = true
                    scanner.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}
#endif
```

- [ ] **Step 4: Write `PairingScreen.swift`**

```swift
#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// Scan the Mac's code, then follow pairing to the end.
struct PairingScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?

    var body: some View {
        VStack(spacing: 20) {
            switch store.pairing {
            case .idle:
                Text("On your Mac, open Lostty → Phone Access → Pair a Phone, then point the camera at the code.")
                    .multilineTextAlignment(.center)
                if QRScannerView.isSupported && cameraAllowed == true {
                    QRScannerView { link in Task { await store.pair(link: link) } }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxHeight: 360)
                } else if cameraAllowed == false {
                    Text("Lostty can't use the camera. Allow it in Settings → Lostty, or on the Mac click Copy Pairing Link and paste it here.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if !QRScannerView.isSupported {
                    Text("This device can't scan codes. On the Mac, click Copy Pairing Link, then paste it here.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Paste Pairing Link") {
                    let link = UIPasteboard.general.string ?? ""
                    Task { await store.pair(link: link) }
                }
            case .finding:
                ProgressView("Looking for your Mac nearby…")
            case .waitingForAllow:
                ProgressView("Click Allow on your Mac.")
            case .testing:
                ProgressView("Connecting over Tailscale…")
            case .failed(let text, let canRetryTest):
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(text).multilineTextAlignment(.center)
                if canRetryTest {
                    Button("Try Again") { Task { await store.retryPairingTest() } }
                } else {
                    Button("Scan Again") { store.resetPairing() }
                }
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Paired. Your Mac's sessions are ready.")
                Button("Done") { dismiss() }
            }
        }
        .padding()
        .navigationTitle("Pair with Mac")
        .toolbar {
            Button("Cancel") { dismiss() }
        }
        .onAppear { store.resetPairing() }
        .task {
            guard QRScannerView.isSupported else { return }
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        .onDisappear {
            if store.pairing == .done { store.resetPairing() }
        }
    }
}
#endif
```

- [ ] **Step 5: Write `WelcomeScreen.swift`**

```swift
#if os(iOS)
import SwiftUI

/// First run: nothing paired or typed yet.
struct WelcomeScreen: View {
    var pair: () -> Void
    var settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Open your Mac's Lostty sessions from here.").font(.title2.bold())
            Label("Install Tailscale on your Mac and this iPhone, signed into the same account.", systemImage: "1.circle")
            Label("On your Mac, open Lostty → Phone Access.", systemImage: "2.circle")
            Label("Tap Pair with Mac.", systemImage: "3.circle")
            Button(action: pair) {
                Text("Pair with Mac").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Advanced Setup", action: settings).font(.footnote)
        }
        .padding()
    }
}
#endif
```

- [ ] **Step 6: Wire the welcome screen and Pair Again into `SessionsScreen`**

Replace `macos/Sources/App/iOS/SessionsScreen.swift` with:

```swift
#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions by project name; the welcome screen while
/// no Mac is set up.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO)?
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var confirmKill: RemoteSession?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.settings.remoteHost == nil {
                    WelcomeScreen(pair: { showPairing = true }, settings: { showSettings = true })
                } else {
                    sessionList
                }
            }
            .navigationTitle("Lostty")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .navigationDestination(for: String.self) { _ in
                if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await refreshIfSetUp() } }) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $showPairing, onDismiss: { Task { await refreshIfSetUp() } }) {
                NavigationStack { PairingScreen() }
            }
            .confirmationDialog(
                "Close \(confirmKill?.name ?? "")?",
                isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } }),
                titleVisibility: .visible,
                presenting: confirmKill
            ) { session in
                Button("Close Session", role: .destructive) {
                    Task { await store.kill(session) }
                }
            } message: { _ in
                Text("This ends the session on the Mac and closes its window there.")
            }
            .task { await refreshIfSetUp() }
            .onChange(of: path) { _, newPath in
                // Back from the terminal: drop it, and refresh the list.
                if newPath.isEmpty {
                    open = nil
                    Task { await refreshIfSetUp() }
                }
            }
        }
    }

    private var sessionList: some View {
        List {
            if let message = store.message {
                Text(message).foregroundStyle(.secondary)
            }
            if store.needsPairing {
                Button("Pair Again") { showPairing = true }
            }
            ForEach(store.sessions, id: \.id) { session in
                Button {
                    guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
                    open = (session, terminal.view, terminal.io)
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
    }

    private func refreshIfSetUp() async {
        if store.settings.remoteHost != nil { await store.refresh() }
    }
}
#endif
```

- [ ] **Step 7: Rewrite `SettingsScreen.swift`**

```swift
#if os(iOS)
import LosttyRemote
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey: String?
    @State private var keyError: String?
    @State private var confirmForget = false
    @State private var showPairing = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Mac") {
                if store.settings.paired {
                    LabeledContent("Paired with", value: store.settings.host)
                    if let date = store.settings.pairedAt {
                        LabeledContent("Since", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Button(store.settings.paired ? "Pair with a Different Mac" : "Pair with Mac") { showPairing = true }
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Address (Tailscale name or IP)", text: $store.settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("User", text: $store.settings.user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $store.settings.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    if let problem = store.settings.problem, !store.settings.host.isEmpty {
                        Text(problem).foregroundStyle(.red)
                    }
                    Button("Show This Phone's Key") {
                        do {
                            publicKey = try store.remoteKey().publicKeyLine
                            keyError = nil
                        } catch {
                            publicKey = nil
                            keyError = (error as? RemoteError)?.message ?? error.localizedDescription
                        }
                    }
                    if let keyError { Text(keyError).foregroundStyle(.red) }
                    if let publicKey {
                        Text(publicKey).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: publicKey)
                    }
                    Button("Forget the Mac's Host Key", role: .destructive) { confirmForget = true }
                }
            } footer: {
                Text("For setting up by hand. Pairing fills these in for you.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Forget the Mac's host key?", isPresented: $confirmForget, titleVisibility: .visible
        ) {
            Button("Forget Host Key", role: .destructive) { store.forgetHostKey() }
        } message: {
            Text("Only do this if the Mac's SSH host key really changed. The next connection trusts whatever key the address offers.")
        }
        .sheet(isPresented: $showPairing) {
            NavigationStack { PairingScreen() }
        }
        .onDisappear { store.saveSettings() }
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

Typing in Advanced edits `host`/`user`/`port` but leaves `pairedAt` and `fallbackHost` as they were; that is fine for the developer's own debugging and is the documented Advanced behavior.

- [ ] **Step 8: Build for the simulator and the Mac**

Run the iOS build check and `macos/build.nu --configuration Debug --action build`.
Expected: both `** BUILD SUCCEEDED **`.
Run: `cd macos/LosttyRemote && swift test`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add macos/Lostty-iOS-Info.plist macos/Sources/App/iOS/QRScannerView.swift macos/Sources/App/iOS/PairingScreen.swift macos/Sources/App/iOS/WelcomeScreen.swift macos/Sources/App/iOS/MobileStore.swift macos/Sources/App/iOS/SessionsScreen.swift macos/Sources/App/iOS/SettingsScreen.swift macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "lostty: phone pairs by scanning the Mac's code; welcome screen, Pair Again, Advanced settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Customer guide and desk checks

The implementer writes the docs; the desk checks are run by the human with the controller, on the real Mac and iPhone.

**Files:**
- Create: `docs/lostty-mobile-phone-access.md`
- Modify: `docs/lostty-mobile-host-setup.md` (title and first paragraph)

- [ ] **Step 1: Write the customer guide**

`docs/lostty-mobile-phone-access.md`:

```markdown
# Lostty on your iPhone

Open your Mac's Lostty sessions from your iPhone, anywhere, over your own
Tailscale. Nothing goes through a Lostty server; there isn't one.

## Set up (once)

1. Install [Tailscale](https://tailscale.com/download) on your Mac and your
   iPhone, and sign in to both with the same account.
2. On the Mac, open Lostty → **Phone Access…**. Fix any row that isn't ✓:
   - **tmux**: `brew install tmux`.
   - **Remote Login** and **Password logins off**: one admin password prompt
     turns on Remote Login and allows only key logins. You can skip turning
     password logins off, but anyone who can reach your Mac could then try
     your password over SSH.
   - **Terminal definition**: click Install.
3. Click **Pair a Phone…**. On the iPhone, open Lostty, tap **Pair with Mac**,
   and scan the code. Click **Allow** on the Mac.

Your phone can reach the Mac only while the Mac is awake and Lostty is open.

## Lost phone

Open Lostty → Phone Access on the Mac and click **Remove** next to it. If you
can't get to Lostty, delete the line ending in `lostty-phone:<id>` from
`~/.ssh/authorized_keys`.

## Turning it off

Phone Access → **Turn Off Phone Access…** removes every paired phone and
offers to turn password logins back on. Remote Login stays as it is; turn it
off in System Settings → General → Sharing if you don't use it.

If you deleted Lostty instead, clean up by hand:

- remove the lines ending in `lostty-phone:…` from `~/.ssh/authorized_keys`;
- `sudo rm /etc/ssh/sshd_config.d/000-lostty.conf` to allow password logins again;
- optionally `rm ~/.terminfo/78/xterm-ghostty ~/.terminfo/67/ghostty`.

## Troubleshooting

- **"Couldn't find your Mac nearby"** while pairing: keep the code open on the
  Mac, keep the phone close, and allow Local Network access for Lostty on both.
- **"Can't reach your Mac"**: check Tailscale is on on both, signed into the
  same account, and the Mac is awake.
- **"This Mac's identity changed"**: if you reinstalled macOS, pair again.
  Otherwise don't connect; something else is answering at that address.
```

In `docs/lostty-mobile-host-setup.md`, change the title and first line to:

```markdown
# Lostty Mobile: manual Mac setup (Advanced)

Most people should use Lostty → Phone Access instead
(docs/lostty-mobile-phone-access.md). These are the steps it automates, for
setting up by hand.
```

- [ ] **Step 2: Commit the docs**

```bash
git add docs/lostty-mobile-phone-access.md docs/lostty-mobile-host-setup.md
git commit -m "docs: Lostty Mobile Phone Access guide

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Desk checks (human, real devices)**

Install the Debug Mac build and the iPhone build (as in phase 3), then with the controller:

1. Phone Access shows every row; on this Mac all are ✓ except **Password logins off** and **Terminal definition**.
2. **Install** terminfo → ✓. **Turn Off Password Logins…** → one admin prompt → ✓; `ssh -o PreferredAuthentications=password localhost` is refused.
3. **Pair a Phone…** → QR. On the phone: Pair with Mac → scan → Allow on the Mac (it says “iPhone 13”) → the phone lands on the session list.
4. Turn off the phone's Wi-Fi; on cellular, open a session and type.
5. Deny once; let a code expire; scan a used code: each shows its message and nothing is added to `authorized_keys`.
6. **Remove** the phone → the phone shows "Your Mac doesn't accept this phone anymore." with Pair Again.
7. **Turn Off Phone Access…** → Turn Back On → `ssh -o PreferredAuthentications=none localhost` lists `password` again; then lock down again.
8. In a phone session, `cat` a file in `~/Documents`: same result as in the Mac window.
9. With the developer's OK, remove the two hand-added `lostty-mobile` lines from `~/.ssh/authorized_keys` and the old `200-lostty.conf` if present.
```
