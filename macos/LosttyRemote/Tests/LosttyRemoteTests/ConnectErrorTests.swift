import Citadel
import Foundation
import LocalAuthentication
import Testing
@testable import LosttyRemote

struct ConnectErrorTests {
    struct Boom: Error {}

    @Test func aCancelledTouchIDIsAHardStop() {
        for code in [LAError.userCancel, .appCancel, .systemCancel, .authenticationFailed, .userFallback] {
            #expect(RemoteError.mapConnectError(LAError(code)) as? RemoteError == .authenticationCancelled)
        }
    }

    @Test func anLAErrorDomainNSErrorIsToo() {
        let error = NSError(domain: LAError.errorDomain, code: -2)
        #expect(RemoteError.mapConnectError(error) as? RemoteError == .authenticationCancelled)
    }

    @Test func aSecurityUserCanceledStatusIsToo() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -128)
        #expect(RemoteError.mapConnectError(error) as? RemoteError == .authenticationCancelled)
    }

    @Test func aWrappedCancelIsFound() {
        let error = NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: LAError(.userCancel)])
        #expect(RemoteError.mapConnectError(error) as? RemoteError == .authenticationCancelled)
    }

    @Test func otherErrorsPassThrough() {
        #expect(RemoteError.mapConnectError(RemoteError.keyRejected) as? RemoteError == .keyRejected)
        #expect(RemoteError.mapConnectError(Boom()) is Boom)
    }

    @Test func refusedKeyReadsAsKeyRejected() {
        #expect(RemoteError.mapConnectError(SSHClientError.allAuthenticationOptionsFailed) as? RemoteError == .keyRejected)
        let other = RemoteError.mapConnectError(SSHClientError.channelCreationFailed)
        #expect((other as? SSHClientError).map { if case .channelCreationFailed = $0 { true } else { false } } == true)
    }
}
