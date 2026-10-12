import Foundation
import NIOCore
import Testing
@testable import LosttyRemote

struct DescribeErrorTests {
    let host = RemoteHost(host: "mac.tail.ts.net", port: 2222, user: "u", terminfoDir: "/t")
    let unreachable = "Couldn't reach the Mac at mac.tail.ts.net:2222. Check the address, and that Tailscale and Remote Login are on."

    @Test func networkFailuresReadAsUnreachable() {
        #expect(RemoteError.describe(ChannelError.connectTimeout(.seconds(10)), host: host) == unreachable)
        #expect(RemoteError.describe(ChannelError.ioOnClosedChannel, host: host) == unreachable)
        for code in [ECONNREFUSED, EHOSTUNREACH, ENETUNREACH] {
            #expect(RemoteError.describe(IOError(errnoCode: code, reason: "connect"), host: host) == unreachable)
        }
        #expect(RemoteError.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED)), host: host) == unreachable)
    }

    @Test func remoteErrorsKeepTheirOwnMessage() {
        #expect(RemoteError.describe(RemoteError.keyRejected, host: host) == RemoteError.keyRejected.message)
        #expect(RemoteError.describe(RemoteError.tmuxMissing, host: host)
            == "tmux isn't installed on the Mac (Lostty looks in /opt/homebrew/bin and /usr/local/bin).")
    }

    @Test func otherErrorsKeepTheSystemText() {
        let error = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "odd"])
        #expect(RemoteError.describe(error, host: host) == "odd")
        #expect(RemoteError.describe(IOError(errnoCode: EPERM, reason: "x"), host: host) != unreachable)
    }
}
