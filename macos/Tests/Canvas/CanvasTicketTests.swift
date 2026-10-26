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
        var ticket = CanvasTicket(key: "LT-3", summary: "Fix login", kind: .story, priority: .lowest,
                                  assignee: "Sam", details: "Drops after 8s", zone: UUID())
        ticket.move(to: .working, by: .lostty(agent: UUID()))
        ticket.move(to: .blocked, note: "Needs the API key", by: .owner)
        #expect(try JSONDecoder().decode(CanvasTicket.self, from: JSONEncoder().encode(ticket)) == ticket)
    }

    @Test func whatANewerBuildSavedComesBackWithDefaults() throws {
        // A state, type and priority this build doesn't know, a field it
        // doesn't have, and the rest missing.
        let json = #"{"key":"LT-9","summary":"Later","kind":"epic","priority":"urgent","state":"parked","sprint":4}"#
        let ticket = try JSONDecoder().decode(CanvasTicket.self, from: Data(json.utf8))
        #expect(ticket == CanvasTicket(key: "LT-9", summary: "Later"))
    }

    @Test func aTicketSavedBeforeTheBoardTakesItsStateFromItsStatus() throws {
        func state(_ status: String) throws -> CanvasTicket.State {
            let json = #"{"key":"LT-1","summary":"Old","status":"\#(status)"}"#
            return try JSONDecoder().decode(CanvasTicket.self, from: Data(json.utf8)).state
        }
        #expect(try state("toDo") == .queued)
        #expect(try state("inProgress") == .working)
        #expect(try state("done") == .done)
        #expect(try state("inReview") == .queued)
    }

    @Test func anOlderBuildReadsTheStatusAFinishedTicketIsSavedWith() throws {
        func status(_ state: CanvasTicket.State) throws -> String? {
            let data = try JSONEncoder().encode(CanvasTicket(key: "LT-1").moved(to: state))
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
        }
        #expect(try status(.done) == "done")
        #expect(try status(.working) == "inProgress")
        #expect(try status(.queued) == "toDo")
        #expect(try status(.review) == "toDo")
        #expect(try status(.blocked) == "toDo")
    }

    @Test func eachActorMovesOnlyWhatTheLifecycleAllows() {
        let pane = UUID(), domain = UUID(), project = UUID()
        let moves = CanvasTicket.State.allCases.flatMap { from in CanvasTicket.State.allCases.map { (from, $0) } }
        func allowed(_ actor: TicketActor) -> [String] {
            moves.filter { $0.0.allows($0.1, by: actor) }.map { "\($0.0)>\($0.1)" }
        }
        #expect(allowed(.lostty(agent: pane)) == ["queued>working"])
        #expect(allowed(.agent(domain: domain)) == ["working>review", "working>blocked"])
        #expect(allowed(.manager(project: project)).isEmpty)
        // The owner moves anything anywhere but to working, which only
        // Lostty typing the ticket does: 25 moves less 5 to the same state
        // and 4 to working.
        let owner = allowed(.owner)
        #expect(owner.count == 16)
        #expect(!owner.contains { $0.hasSuffix(">working") })
    }

    @Test func anAgentMovesOnlyATicketInItsOwnDomain() {
        let login = UUID(), onboarding = UUID(), pane = UUID()
        var ticket = CanvasTicket(key: "TB-7", zone: login)
        let typed = ticket.move(to: .working, by: .lostty(agent: pane))
        #expect(typed)
        #expect(ticket.agentPane == pane)
        let elsewhere = ticket.move(to: .review, note: "Done", by: .agent(domain: onboarding))
        #expect(!elsewhere)
        #expect(ticket.state == .working)
        let reviewed = ticket.move(to: .review, note: "Added the button", by: .agent(domain: login))
        #expect(reviewed)
        #expect(ticket.note == "Added the button")
        // Said again, it changes nothing.
        let again = ticket.move(to: .review, note: "Again", by: .agent(domain: login))
        #expect(!again)
        #expect(ticket.note == "Added the button")
    }

    @Test func undoPutsBackTheStateNoteAndFeature() {
        let login = UUID(), onboarding = UUID()
        let before = CanvasTicket(key: "TB-7", zone: login).moved(to: .review)
        var after = before
        after.move(to: .done, by: .owner)
        after.zone = onboarding
        var now = after
        now.summary = "Renamed"
        let undone = now.reverting(after, to: before)
        #expect(undone.state == .review)
        #expect(undone.zone == login)
        #expect(undone.summary == "Renamed")
    }
}

extension CanvasTicket {
    /// This ticket in `state`, moved there as the board and Lostty would.
    func moved(to state: State) -> CanvasTicket {
        var ticket = self
        ticket.move(to: state, by: state == .working ? .lostty(agent: UUID()) : .owner)
        return ticket
    }
}
#endif
