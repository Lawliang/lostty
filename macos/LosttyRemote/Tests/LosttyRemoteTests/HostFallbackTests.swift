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
