#if os(macOS)
import Testing
@testable import Ghostty

struct AttachedPhonesTests {
    // pid: (ppid, name)
    let table: [Int32: (Int32, String)] = [
        500: (400, "tmux"), 400: (300, "zsh"), 300: (200, "sshd-session"), 200: (1, "sshd"),  // over SSH
        600: (550, "tmux"), 550: (1, "Lostty"),                                             // Mac window
        700: (690, "tmux"), 690: (1, "sshd"),                                               // older sshd name
    ]

    func parent(_ pid: Int32) -> (ppid: Int32, name: String)? { table[pid].map { (ppid: $0.0, name: $0.1) } }

    @Test func anySSHClientCountsAndMacClientsDont() {
        let clients = "500\tapi-server\n600\tidfk\n700\tapi-server\n"
        #expect(AttachedPhones.sessions(clients: clients, parent: parent) == ["api-server"])
    }

    @Test func junkAndUnknownPidsAreIgnored() {
        #expect(AttachedPhones.sessions(clients: "x\ty\n\n999\tlost\n", parent: parent) == [])
    }

    @Test func aLoopInTheTableEnds() {
        let loop: (Int32) -> (ppid: Int32, name: String)? = { pid in (ppid: pid == 10 ? 11 : 10, name: "zsh") }
        #expect(AttachedPhones.sessions(clients: "10\ts\n", parent: loop) == [])
    }
}
#endif
