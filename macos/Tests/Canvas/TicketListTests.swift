#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TicketListTests {
    private func ticket(
        _ number: Int, _ status: CanvasTicket.Status = .toDo, _ priority: CanvasTicket.Priority = .medium
    ) -> CanvasTicket {
        CanvasTicket(key: "LT-\(number)", summary: "Ticket \(number)", priority: priority, status: status)
    }

    @Test func sectionsGoInProgressThenUpNextThenCompleted() {
        let list = TicketList(tickets: [ticket(1, .done), ticket(2, .toDo), ticket(3, .inProgress)])
        #expect(list.shown == ["LT-3", "LT-2", "LT-1"])
        // The first row is selected.
        #expect(list.selected == "LT-3")
    }

    @Test func upNextIsHighestPriorityFirstThenOldest() {
        let list = TicketList(tickets: [ticket(1, .toDo, .low), ticket(2, .toDo, .highest), ticket(3, .toDo, .low)])
        #expect(list.tickets(in: .toDo).compactMap(\.key) == ["LT-2", "LT-1", "LT-3"])
    }

    @Test func completedIsLatestDoneFirst() {
        var list = TicketList(tickets: [ticket(1, .done), ticket(2, .toDo), ticket(3, .done)])
        list.update(ticket(2, .done))
        #expect(list.tickets(in: .done).compactMap(\.key) == ["LT-2", "LT-3", "LT-1"])
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
        var list = TicketList(tickets: [ticket(1, .inProgress), ticket(2, .toDo), ticket(3, .done)])
        list.fold(.toDo)
        list.move(by: 1)
        #expect(list.selected == "LT-3")
    }

    @Test func foldingTheSelectedTicketsSectionSelectsTheNextSectionsFirst() {
        var list = TicketList(tickets: [ticket(1, .inProgress), ticket(2, .toDo), ticket(3, .done)])
        list.fold(.inProgress)
        #expect(list.selected == "LT-2")
        // Nothing after it: the last row showing.
        list.selected = "LT-3"
        list.fold(.done)
        #expect(list.selected == "LT-2")
    }

    @Test func aMovedTicketStaysSelectedAndItsSectionUnfolds() {
        var list = TicketList(tickets: [ticket(1, .toDo), ticket(2, .toDo)])
        list.fold(.done)
        list.selected = "LT-1"
        list.update(ticket(1, .done))
        #expect(list.selected == "LT-1")
        #expect(!list.folded.contains(.done))
        #expect(list.shown == ["LT-2", "LT-1"])
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

    @Test func statusesCycleRound() {
        #expect(CanvasTicket.Status.toDo.next == .inProgress)
        #expect(CanvasTicket.Status.inProgress.next == .done)
        #expect(CanvasTicket.Status.done.next == .toDo)
    }

    @Test func undoingAChangeLeavesWhatChangedSince() {
        let before = ticket(1, .toDo, .low)
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
