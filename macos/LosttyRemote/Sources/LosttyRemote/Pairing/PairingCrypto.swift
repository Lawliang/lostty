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
