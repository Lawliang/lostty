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

    @Test func onlyTypingAsksBeforeADraftIsThrownAway() {
        // Picking a type or priority alone isn't worth asking about.
        #expect(!CanvasTicket(kind: .bug, priority: .high).hasTyping)
        #expect(!CanvasTicket(summary: " ", details: "\n").hasTyping)
        #expect(CanvasTicket(assignee: "Sam").hasTyping)
        #expect(CanvasTicket(details: "Drops after 8s").hasTyping)
    }

    @Test func aTicketComesBackAsItWas() throws {
        let ticket = CanvasTicket(key: "LT-3", summary: "Fix login", kind: .story, priority: .lowest, status: .done,
                                  assignee: "Sam", details: "Drops after 8s")
        #expect(try JSONDecoder().decode(CanvasTicket.self, from: JSONEncoder().encode(ticket)) == ticket)
    }

    @Test func whatANewerBuildSavedComesBackWithDefaults() throws {
        // A status, type and priority this build doesn't know, a field it
        // doesn't have, and the rest missing.
        let json = #"{"key":"LT-9","summary":"Later","kind":"epic","priority":"urgent","status":"inReview","sprint":4}"#
        let ticket = try JSONDecoder().decode(CanvasTicket.self, from: Data(json.utf8))
        #expect(ticket == CanvasTicket(key: "LT-9", summary: "Later"))
    }
}
#endif
