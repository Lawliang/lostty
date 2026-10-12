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
