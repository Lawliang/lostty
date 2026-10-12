import Citadel
import Crypto
import CryptoKit
import Foundation
import LocalAuthentication
import NIOCore
import NIOSSH

public enum RemoteError: Error, Equatable {
    case secureEnclaveUnavailable
    case hostKeyChanged(host: String, pinned: String, offered: String)
    case keyRejected
    case authenticationCancelled

    case tmuxMissing
    case notPaired

    public var message: String {
        switch self {
        case .secureEnclaveUnavailable:
            "This device has no Secure Enclave to keep the Lostty Mobile key in."
        case .hostKeyChanged(let host, let pinned, _):
            Self.hostKeyChangedMessage(host: host, pinned: pinned)
        case .keyRejected:
            Self.keyRejectedMessage
        case .authenticationCancelled:
            Self.authCancelledMessage
        case .tmuxMissing:
            "tmux isn't installed on the Mac (Lostty looks in /opt/homebrew/bin and /usr/local/bin)."
        case .notPaired:
            "Pair this iPhone with your Mac first."
        }
    }

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
}

extension RemoteError {
    /// Citadel hands the connect the original error NIOSSH hit while signing
    /// the auth offer with the Secure Enclave key (it reaches the handshake
    /// through fireErrorCaught unwrapped). A cancelled or failed user-presence
    /// check is a hard stop: retrying would prompt Touch ID again and again.
    /// Anything else passes through unchanged. Citadel's login timeout is a
    /// fixed 10 s, so a prompt left unanswered also ends here as a plain
    /// timeout (retried by the caller).
    static func mapConnectError(_ error: Error) -> Error {
        if isUserPresenceFailure(error) { return RemoteError.authenticationCancelled }
        // Citadel replaces our KeyAuth's own error with this one when the
        // server refuses the key.
        if let ssh = error as? SSHClientError, case .allAuthenticationOptionsFailed = ssh {
            return RemoteError.keyRejected
        }
        return error
    }

    /// What to show for any error from connecting or listing: Lostty's own
    /// messages, a plain "couldn't reach" for network failures (otherwise
    /// the user sees "NIOCore.ChannelError error 0"), else the system text.
    public static func describe(_ error: Error, host: RemoteHost) -> String {
        if let remote = error as? RemoteError { return remote.message }
        if isUnreachable(error) {
            #if os(iOS)
            return "Can't reach your Mac. Is Tailscale on here and on the Mac, and is the Mac awake?"
            #else
            return "Couldn't reach the Mac at \(host.host):\(host.port). "
                + "Check the address, and that Tailscale and Remote Login are on."
            #endif
        }
        return error.localizedDescription
    }

    private static let unreachableErrnos: Set<Int32> = [
        ECONNREFUSED, EHOSTUNREACH, ENETUNREACH, ENETDOWN, ETIMEDOUT, EHOSTDOWN, ECONNRESET, ECONNABORTED,
    ]

    public static func isUnreachable(_ error: Error) -> Bool {
        if error is ChannelError { return true }
        // NIOConnectionError (all addresses failed, DNS included) is in
        // NIOPosix, which this package doesn't import directly.
        if String(describing: type(of: error)) == "NIOConnectionError" { return true }
        if let io = error as? IOError { return unreachableErrnos.contains(io.errnoCode) }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return unreachableErrnos.contains(Int32(ns.code)) }
        if ns.domain == NSURLErrorDomain {
            return [NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut,
                    NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet].contains(ns.code)
        }
        return false
    }

    private static func isUserPresenceFailure(_ error: Error) -> Bool {
        if error is LAError { return true }
        let ns = error as NSError
        if ns.domain == LAError.errorDomain { return true }
        // Security reports a cancelled user-presence check as errSecUserCanceled
        // (-128), errSecAuthFailed (-25293) or errSecInteractionNotAllowed (-25308).
        if ns.domain == NSOSStatusErrorDomain, [-128, -25293, -25308].contains(ns.code) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return isUserPresenceFailure(underlying)
        }
        return false
    }
}

/// The SSH key: an ECDSA P-256 key in the Secure Enclave (which does not do
/// ed25519), used behind user presence. Only the Secure Enclave's wrapped
/// handle is stored on disk; it is useless on any other device.
public struct RemoteKey: @unchecked Sendable {
    let privateKey: NIOSSHPrivateKey

    /// "ecdsa-sha2-nistp256 AAAA… lostty-mobile", for authorized_keys.
    public let publicKeyLine: String

    public init(software key: P256.Signing.PrivateKey) {
        self.init(NIOSSHPrivateKey(p256Key: key))
    }

    init(_ key: NIOSSHPrivateKey) {
        privateKey = key
        publicKeyLine = String(openSSHPublicKey: key.publicKey) + " lostty-mobile"
    }

    /// Loads the key whose handle is at `url`, creating it on first use.
    /// Signing asks for Face ID / Touch ID through `context`: pass the same
    /// `LAContext` for every connection and it asks once, until the context
    /// is invalidated (the app invalidates it when it goes to the background).
    public static func secureEnclave(storedAt url: URL, context: LAContext? = nil) throws -> RemoteKey {
        guard SecureEnclave.isAvailable else { throw RemoteError.secureEnclaveUnavailable }
        // Never replace an existing handle: that would silently invalidate the
        // authorized_keys line. If it exists but can't be used, throw.
        if FileManager.default.fileExists(atPath: url.path) {
            return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key:
                try SecureEnclave.P256.Signing.PrivateKey(
                    dataRepresentation: Data(contentsOf: url), authenticationContext: context)))
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error)
        else { throw error?.takeRetainedValue() ?? RemoteError.secureEnclaveUnavailable }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: context)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.dataRepresentation.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key: key))
    }

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
}

/// Offers the key once; a second request means the server refused it.
final class KeyAuth: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let user: String
    private let key: NIOSSHPrivateKey
    private var offered = false

    init(user: String, key: RemoteKey) {
        self.user = user
        self.key = key.privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(RemoteError.keyRejected)
            return
        }
        offered = true
        nextChallengePromise.succeed(.init(
            username: user, serviceName: "", offer: .privateKey(.init(privateKey: key))))
    }
}

/// Pins the host key on first connect; a different key later is a hard stop.
final class PinnedHostKeys: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let knownHosts: KnownHosts

    init(host: String, port: Int, knownHosts: KnownHosts) {
        self.host = host
        self.port = port
        self.knownHosts = knownHosts
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let offered = String(openSSHPublicKey: hostKey)
        switch knownHosts.verdict(host: host, port: port, key: offered) {
        case .trusted:
            validationCompletePromise.succeed(())
        case .unknown:
            do {
                try knownHosts.trust(host: host, port: port, key: offered)
                validationCompletePromise.succeed(())
            } catch {
                validationCompletePromise.fail(error)
            }
        case .changed(let pinned):
            validationCompletePromise.fail(RemoteError.hostKeyChanged(host: host, pinned: pinned, offered: offered))
        }
    }
}
