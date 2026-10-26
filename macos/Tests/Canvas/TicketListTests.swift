#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TicketListTests {
    private let login = UUID(), onboarding = UUID(), project = UUID()

    private func ticket(
        _ number: Int, _ state: CanvasTicket.State = .queued, in zone: UUID? = nil, _ priority: CanvasTicket.Priority = .medium
    ) -> CanvasTicket {
        CanvasTicket(key: "LT-\(number)", summary: "Ticket \(number)", priority: priority, zone: zone).moved(to: state)
    }

    /// A project's panel: Login, Onboarding, then To assign.
    private func board(_ tickets: [CanvasTicket], selected: String? = nil, folded: Set<TicketSection> = []) -> TicketList {
        TicketList(
            tickets: tickets, zones: [project, login, onboarding], sections: [.feature(login), .feature(onboarding), .toAssign],
            selected: selected, folded: folded)
    }

    @Test func eachFeatureHasASectionThenToAssign() {
        let list = board([ticket(1, in: project), ticket(2, in: onboarding), ticket(3, in: login), ticket(4)])
        #expect(list.tickets(in: .feature(login)).compactMap(\.key) == ["LT-3"])
        #expect(list.tickets(in: .feature(onboarding)).compactMap(\.key) == ["LT-2"])
        // A ticket in no zone doesn't show in a project's panel.
        #expect(list.tickets(in: .toAssign).compactMap(\.key) == ["LT-1"])
        #expect(list.shown == ["LT-3", "LT-2", "LT-1"])
    }

    @Test func aFeatureShowsItsWorkingTicketThenItsQueueInOrderThenWhatWaitsThenDoneLatestFirst() {
        let list = board([
            ticket(1, .done, in: login), ticket(2, .queued, in: login, .lowest), ticket(3, .review, in: login),
            ticket(4, .queued, in: login, .highest), ticket(5, .working, in: login), ticket(6, .blocked, in: login),
            ticket(7, .done, in: login),
        ])
        // Priority doesn't reorder the queue: it's the order Lostty types.
        #expect(list.tickets(in: .feature(login)).compactMap(\.key) == ["LT-5", "LT-2", "LT-4", "LT-3", "LT-6", "LT-7", "LT-1"])
    }

    @Test func withoutZonesEveryTicketIsInOneSection() {
        let list = TicketList(tickets: [ticket(1, .done), ticket(2, .queued), ticket(3, .working)])
        #expect(list.sections == [.toAssign])
        #expect(list.shown == ["LT-3", "LT-2", "LT-1"])
        // The first row is selected.
        #expect(list.selected == "LT-3")
    }

    @Test func aPanelInAZoneListsOnlyItsZonesTickets() {
        let tickets = [ticket(1, in: login), ticket(2, in: onboarding), ticket(3, .done, in: login)]
        let list = TicketList(tickets: tickets, zones: [login], sections: [.feature(login)], selected: "LT-2", folded: [])
        #expect(list.shown == ["LT-1", "LT-3"])
        #expect(list.count(.queued) == 1)
        #expect(list.selected == nil)
    }

    @Test func draftsArentListed() {
        let list = TicketList(tickets: [CanvasTicket(summary: "Half typed"), ticket(1)])
        #expect(list.tickets.compactMap(\.key) == ["LT-1"])
    }

    @Test func theSelectionStopsAtTheEnds() {
        var list = TicketList(tickets: [ticket(1), ticket(2)])
        list.move(by: -1)
        #expect(list.selected == "LT-1")
        list.move(by: 1)
        list.move(by: 1)
        #expect(list.selected == "LT-2")
    }

    @Test func movingSkipsFoldedSections() {
        var list = board([ticket(1, in: login), ticket(2, in: onboarding), ticket(3, in: project)], selected: "LT-1")
        list.fold(.feature(onboarding))
        list.move(by: 1)
        #expect(list.selected == "LT-3")
    }

    @Test func foldingTheSelectedTicketsSectionSelectsTheNextSectionsFirst() {
        var list = board([ticket(1, in: login), ticket(2, in: onboarding), ticket(3, in: project)], selected: "LT-1")
        list.fold(.feature(login))
        #expect(list.selected == "LT-2")
        // Nothing after it: the last row showing.
        list.selected = "LT-3"
        list.fold(.toAssign)
        #expect(list.selected == "LT-2")
    }

    @Test func anAssignedTicketGoesToTheBackOfItsFeatureAndItsSectionUnfolds() {
        var list = board(
            [ticket(1, .blocked, in: login), ticket(2, in: onboarding), ticket(3, in: onboarding)],
            selected: "LT-1", folded: [.feature(onboarding)])
        list.assign("LT-1", to: onboarding)
        #expect(list.selected == "LT-1")
        #expect(!list.folded.contains(.feature(onboarding)))
        #expect(list.tickets(in: .feature(onboarding)).compactMap(\.key) == ["LT-2", "LT-3", "LT-1"])
        #expect(list.ticket("LT-1")?.state == .queued)
    }

    @Test func aTicketMovedToDoneShowsFirstAmongTheDone() {
        var list = board([ticket(1, .done, in: login), ticket(2, .review, in: login), ticket(3, .done, in: login)])
        list.update(ticket(2, .done, in: login))
        #expect(list.tickets(in: .feature(login)).compactMap(\.key) == ["LT-2", "LT-3", "LT-1"])
    }

    @Test func deletingSelectsTheRowBelowElseAbove() throws {
        var list = TicketList(tickets: [ticket(1), ticket(2), ticket(3)])
        list.selected = "LT-2"
        let taken = list.remove("LT-2")
        let removed = try #require(taken)
        #expect(removed.index == 1)
        #expect(list.selected == "LT-3")
        list.remove("LT-3")
        #expect(list.selected == "LT-1")
        list.remove("LT-1")
        #expect(list.selected == nil)
    }

    @Test func aDeletedTicketComesBackWhereItWas() throws {
        var list = TicketList(tickets: [ticket(1), ticket(2), ticket(3)])
        let taken = list.remove("LT-2")
        let removed = try #require(taken)
        list.add(removed.ticket, at: removed.index)
        #expect(list.tickets.compactMap(\.key) == ["LT-1", "LT-2", "LT-3"])
        #expect(list.selected == "LT-2")
    }

    @Test func mergingSkipsTicketsAlreadyThere() {
        var list = TicketList(tickets: [ticket(1)])
        var renamed = ticket(1)
        renamed.summary = "Renamed elsewhere"
        list.merge([renamed, ticket(2)])
        #expect(list.tickets.map(\.summary) == ["Ticket 1", "Ticket 2"])
    }

    @Test func statesCycleRoundWhatTheOwnerCanSet() {
        #expect(CanvasTicket.State.queued.next == .review)
        #expect(CanvasTicket.State.review.next == .done)
        #expect(CanvasTicket.State.done.next == .blocked)
        #expect(CanvasTicket.State.blocked.next == .queued)
        #expect(CanvasTicket.State.working.next == .queued)
    }

    @Test func undoingAChangeLeavesWhatChangedSince() {
        let before = ticket(1, .queued, .low)
        var after = before
        after.priority = .high
        // Renamed after the priority changed.
        var now = after
        now.summary = "Renamed"
        let undone = now.reverting(after, to: before)
        #expect(undone.priority == .low)
        #expect(undone.summary == "Renamed")
    }
}
#endif
