import Citadel
import Crypto
import CryptoKit
import Foundation
import NIOCore
import NIOSSH

public enum RemoteError: Error, Equatable {
    case secureEnclaveUnavailable
    case hostKeyChanged(host: String, pinned: String, offered: String)
    case keyRejected

    public var message: String {
        switch self {
        case .secureEnclaveUnavailable:
            "This Mac has no Secure Enclave to keep the Lostty Mobile key in."
        case .hostKeyChanged(let host, let pinned, _):
            "The SSH host key for \(host) changed since it was first trusted (pinned \(pinned.prefix(40))…). "
                + "Lostty will not connect. If the Mac's key really changed, remove its line from known_hosts in "
                + "Application Support/Lostty."
        case .keyRejected:
            "The Mac refused Lostty's key. Add the line from \"Copy Remote Key\" to ~/.ssh/authorized_keys."
        }
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
    public static func secureEnclave(storedAt url: URL) throws -> RemoteKey {
        guard SecureEnclave.isAvailable else { throw RemoteError.secureEnclaveUnavailable }
        // Never replace an existing handle: that would silently invalidate the
        // authorized_keys line. If it exists but can't be used, throw.
        if FileManager.default.fileExists(atPath: url.path) {
            return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key:
                try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: Data(contentsOf: url))))
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error)
        else { throw error?.takeRetainedValue() ?? RemoteError.secureEnclaveUnavailable }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.dataRepresentation.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key: key))
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
