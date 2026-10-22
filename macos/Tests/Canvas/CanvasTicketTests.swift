#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct CanvasTicketTests {
    @Test func theFirstTicketIsLT1() {
        #expect(CanvasTicket.nextKey(after: []) == "LT-1")
    }

    @Test func aNewTicketGoesOnePastTheHighestNumber() {
        #expect(CanvasTicket.nextKey(after: ["LT-1", "LT-4", "LT-2"]) == "LT-5")
    }

    @Test func aClosedTicketsNumberIsNotHandedOutAgain() {
        // LT-7 was the last made, then closed: only LT-2 is left.
        #expect(CanvasTicket.nextKey(after: ["LT-2"], lastNumber: 7) == "LT-8")
    }

    @Test func otherKeysDontCount() {
        #expect(CanvasTicket.nextKey(after: ["ABC-9", "LT-x", "LT-"]) == "LT-1")
    }

    @Test func aKeysNumber() {
        #expect(CanvasTicket.number(of: "LT-12") == 12)
        #expect(CanvasTicket.number(of: "LTX-1") == nil)
        #expect(CanvasTicket.number(of: "LT-") == nil)
    }

    @Test func aTicketNeedsASummary() {
        #expect(!CanvasTicket().canSave)
        #expect(!CanvasTicket(summary: "  \n ").canSave)
        #expect(CanvasTicket(summary: "Fix login").canSave)
    }

    @Test func aDraftHasNoKeyUntilItsCreated() {
        #expect(!CanvasTicket(summary: "Fix login").isCreated)
        #expect(CanvasTicket(key: "LT-1", summary: "Fix login").isCreated)
    }
}
#endif
