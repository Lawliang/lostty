#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ApprovalBookTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func check(_ input: String = "git push", pane: String = "P1") -> GuardCheck {
        GuardCheck(v: 1, pane: pane, agent: "claude", session: "s", tool: "Bash", input: input, cwd: "/r",
                   repo: "/r", branch: "feature", group: "leaving", why: "git push sends commits off this Mac",
                   lost: nil, reason: nil)
    }

    @Test func aNewCallIsDeniedWithARequest() {
        var book = ApprovalBook()
        let (reply, isNew) = book.check(check(), now: t0)
        #expect(reply == .deny(1))
        #expect(isNew)
        #expect(book.pending.map(\.id) == [1])
    }

    @Test func askingAgainReusesThePendingRequest() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        let (reply, isNew) = book.check(check(), now: t0 + 5)
        #expect(reply == .deny(1))
        #expect(!isNew)
        #expect(book.pending.count == 1)
    }

    @Test func anApprovalLetsExactlyThatCallThroughOnce() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        let r1 = book.approve(1, now: t0 + 10)
        #expect(r1)
        let r2 = book.check(check("git push --force"), now: t0 + 20).reply
        #expect(r2 == .deny(2))
        let r3 = book.check(check(pane: "P2"), now: t0 + 20).reply
        #expect(r3 == .deny(3))
        let r4 = book.check(check(), now: t0 + 30).reply
        #expect(r4 == .allow)
        #expect(book.request(1)?.state == .used)
        // Used up: the same call asks again.
        let r5 = book.check(check(), now: t0 + 40).reply
        #expect(r5 == .deny(4))
    }

    @Test func anApprovalLapsesAfterTenMinutes() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        _ = book.approve(1, now: t0)
        let r6 = book.check(check(), now: t0 + 601).reply
        #expect(r6 == .deny(2))
        #expect(book.request(1)?.state == .expired)
    }

    @Test func requestsLapseAfterAnHour() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        let r7 = book.expire(now: t0 + 3599)
        #expect(r7.isEmpty)
        let r8 = book.expire(now: t0 + 3601)
        #expect(r8 == [1])
        #expect(book.pending.isEmpty)
        let r9 = book.approve(1, now: t0 + 3602)
        #expect(!r9)
    }

    @Test func denyingStopsItAndOnlyPendingCanBeDecided() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        let r10 = book.deny(1, now: t0 + 1)
        #expect(r10)
        let r11 = book.approve(1, now: t0 + 2)
        #expect(!r11)
        let r12 = book.deny(1, now: t0 + 2)
        #expect(!r12)
        let r13 = book.check(check(), now: t0 + 3).reply
        #expect(r13 == .deny(2))
    }

    @Test func approvalsDontSurviveARestart() throws {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        _ = book.approve(1, now: t0)
        let data = try JSONEncoder().encode(book.persisted())
        var loaded = try JSONDecoder().decode(ApprovalBook.self, from: data)
        #expect(loaded.request(1)?.state == .pending)
        let r14 = loaded.check(check(), now: t0 + 1).reply
        #expect(r14 == .deny(1))
    }

    @Test func historyIsCapped() {
        var book = ApprovalBook()
        for i in 0..<150 {
            _ = book.check(check("cmd \(i)"), now: t0)
            _ = book.deny(i + 1, now: t0)
        }
        #expect(book.requests.count <= ApprovalBook.historyLimit)
        #expect(book.nextID == 151)
    }

    func write(_ content: String, tool: String = "Write", input: String = "/Users/me/notes.md") -> GuardCheck {
        var c = check(input)
        c.tool = tool
        c.toolInput = #"{"content":"\#(content)","file_path":"/Users/me/notes.md"}"#
        return c
    }

    @Test func twoWritesToOnePathWithDifferentContentDontShareAnApproval() {
        var book = ApprovalBook()
        _ = book.check(write("one"), now: t0)
        _ = book.approve(1, now: t0 + 1)
        #expect(book.check(write("two"), now: t0 + 2).reply == .deny(2))
        #expect(book.check(write("one"), now: t0 + 3).reply == .allow)
    }

    @Test func mcpCallsWithDifferentArgumentsDontShareAnApproval() {
        func mcp(_ branch: String) -> GuardCheck {
            var c = check("mcp__gh__delete_branch")
            c.tool = "mcp__gh__delete_branch"
            c.toolInput = #"{"branch":"\#(branch)","repo":"o/r"}"#
            return c
        }
        var book = ApprovalBook()
        _ = book.check(mcp("old"), now: t0)
        _ = book.approve(1, now: t0 + 1)
        #expect(book.check(mcp("main"), now: t0 + 2).reply == .deny(2))
        #expect(book.check(mcp("old"), now: t0 + 3).reply == .allow)
    }

    @Test func theKeyComparesFieldsNotAJoinedString() {
        // Joined with a separator these two would be the same string.
        var a = check("b\u{1F}c")
        a.cwd = "/r"
        var b = check("c")
        b.cwd = "/r\u{1F}b"
        #expect(a.key != b.key)
        var withInput = check()
        withInput.toolInput = #"{"command":"git push"}"#
        #expect(withInput.key != check().key)
        #expect(withInput.key == withInput.key)
    }

    @Test func wireDecodesTheGuardsRequest() throws {
        let line = #"{"v":1,"pane":"P","agent":"codex","tool":"Bash","input":"rm x","cwd":"/r","group":"deleting","why":"w","lost":"1 untracked files"}"#
        let c = try JSONDecoder().decode(GuardCheck.self, from: Data(line.utf8))
        #expect(c.agent == "codex")
        #expect(c.repo == nil)
        #expect(c.groupLabel == "Deleting")
        #expect(c.toolInput == nil)
        let big = #"{"v":1,"pane":"P","agent":"claude","tool":"Write","input":"/x","cwd":"/r","group":"outside","why":"w","toolInput":"sha256:ab","toolInputBytes":300000}"#
        let h = try JSONDecoder().decode(GuardCheck.self, from: Data(big.utf8))
        #expect(h.toolInput == "sha256:ab")
        #expect(h.toolInputBytes == 300_000)
        let reply = String(decoding: try JSONEncoder().encode(GuardReply.deny(3)), as: UTF8.self)
        #expect(reply.contains(#""decision":"deny""#))
        #expect(reply.contains(#""request":3"#))
    }
}
#endif
