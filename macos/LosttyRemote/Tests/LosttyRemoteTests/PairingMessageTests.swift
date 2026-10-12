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
