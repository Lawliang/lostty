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

    @Test func aProjectsTicketsNumberApartFromLT() {
        #expect(CanvasTicket.nextKey(prefix: "TB", after: ["LT-4", "TB-2"]) == "TB-3")
        #expect(CanvasTicket.number(of: "TB-2", prefix: "TB") == 2)
        #expect(CanvasTicket.number(of: "LT-2", prefix: "TB") == nil)
    }

    @Test func eachPrefixKeepsItsOwnCountAndLTContinuesFromItsStoredOne() throws {
        let suite = "CanvasTicketTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7, forKey: "LosttyCanvasLastTicketNumber")
        #expect(CanvasTicket.nextKey(prefix: "LT", after: [], defaults: defaults) == "LT-8")
        #expect(CanvasTicket.nextKey(prefix: "LT", after: [], defaults: defaults, take: true) == "LT-8")
        #expect(CanvasTicket.nextKey(prefix: "TB", after: [], defaults: defaults, take: true) == "TB-1")
        #expect(CanvasTicket.nextKey(prefix: "TB", after: [], defaults: defaults, take: true) == "TB-2")
        #expect(CanvasTicket.nextKey(prefix: "LT", after: [], defaults: defaults, take: true) == "LT-9")
        #expect(defaults.integer(forKey: "LosttyCanvasLastTicketNumber") == 9)
    }

    @Test func aTicketsZoneComesBackAndAnOldTicketHasNone() throws {
        let zone = UUID()
        let ticket = CanvasTicket(key: "TB-1", summary: "Sign up", zone: zone)
        #expect(try JSONDecoder().decode(CanvasTicket.self, from: JSONEncoder().encode(ticket)) == ticket)
        let old = try JSONDecoder().decode(CanvasTicket.self, from: Data(#"{"key":"LT-1","summary":"Old"}"#.utf8))
        #expect(old.zone == nil)
    }

    @Test func aTicketInARemovedZoneIsInNoneAndKeepsItsKey() {
        let gone = UUID(), kept = UUID()
        let ticket = CanvasTicket(key: "TB-3", summary: "Sign up", zone: gone)
        #expect(ticket.leaving([gone]).zone == nil)
        #expect(ticket.leaving([gone]).key == "TB-3")
        #expect(CanvasTicket(key: "TB-4", zone: kept).leaving([gone]).zone == kept)
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
