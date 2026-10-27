#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TicketQueueTests {
    private let login = UUID(), onboarding = UUID(), project = UUID(), pane = UUID()

    private func ticket(_ number: Int, _ state: CanvasTicket.State = .queued, in zone: UUID? = nil) -> CanvasTicket {
        CanvasTicket(key: "TB-\(number)", summary: "Ticket \(number)", zone: zone ?? login).moved(to: state)
    }

    private func keys(_ tickets: [CanvasTicket]?) -> [String] {
        tickets?.compactMap(\.key) ?? []
    }

    /// Textberry, with features Login and Onboarding.
    private var textberry: CanvasModel {
        var model = CanvasModel()
        model.addZone(CanvasZone(id: project, frame: CGRect(x: 0, y: 0, width: 4000, height: 2000), name: "Textberry"))
        model.addZone(CanvasZone(
            id: login, frame: CGRect(x: 100, y: 100, width: 1000, height: 1000), name: "Login", parent: project))
        model.addZone(CanvasZone(
            id: onboarding, frame: CGRect(x: 1200, y: 100, width: 1000, height: 1000), name: "Onboarding",
            parent: project))
        return model
    }

    /// `TicketQueue.applying` in Textberry, a new ticket keyed TB-20.
    private func apply(_ report: TicketReport, from actor: TicketActor, to tickets: [CanvasTicket]) -> [CanvasTicket]? {
        TicketQueue.applying(report, from: actor, to: tickets, in: textberry, newKey: { _ in "TB-20" })
    }

    @Test func aFeatureHasOneTicketInFlightAndTheNextStartsOnceItLeavesWorking() throws {
        var tickets = [ticket(1, .working), ticket(2), ticket(3)]
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: []) == nil)
        tickets = try #require(apply(.review(key: "TB-1", note: "Done"), from: .agent(domain: login), to: tickets))
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: [])?.key == "TB-2")
    }

    @Test func withAutoStartOnAFeaturesQueueGoesInOneAtATimeAcrossReviews() throws {
        var tickets = [ticket(1), ticket(2)]
        for key in ["TB-1", "TB-2"] {
            let next = try #require(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: []))
            #expect(next.key == key)
            tickets = try #require(TicketQueue.delivering(key, into: pane, in: tickets))
            #expect(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: []) == nil)
            tickets = try #require(apply(.review(key: key, note: "Done"), from: .agent(domain: login), to: tickets))
        }
        #expect(tickets.map(\.state) == [.review, .review])
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: []) == nil)
    }

    @Test func anotherFeaturesWorkDoesntHoldUpThisOne() {
        let tickets = [ticket(1, .working, in: onboarding), ticket(2)]
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: true, startedByHand: [])?.key == "TB-2")
        #expect(TicketQueue.next(in: onboarding, of: tickets, autoStart: true, startedByHand: []) == nil)
    }

    @Test func withAutoStartOffOnlyATicketTheOwnerStartedGoesIn() {
        let tickets = [ticket(1), ticket(2), ticket(3)]
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: false, startedByHand: []) == nil)
        #expect(TicketQueue.next(in: login, of: tickets, autoStart: false, startedByHand: ["TB-3"])?.key == "TB-3")
    }

    @Test func deliveringMarksTheTicketWorkingInItsPaneOnce() throws {
        let tickets = [ticket(1)]
        let delivered = try #require(TicketQueue.delivering("TB-1", into: pane, in: tickets))
        #expect(delivered[0].state == .working)
        #expect(delivered[0].agentPane == pane)
        #expect(TicketQueue.delivering("TB-1", into: pane, in: delivered) == nil)
    }

    @Test func sendBackPutsTheTicketInFrontOfItsFeaturesQueueWithTheNote() throws {
        let tickets = [ticket(1, .queued, in: onboarding), ticket(2), ticket(3), ticket(4, .review)]
        let sent = try #require(TicketQueue.sendingBack("TB-4", note: "Use the brand blue", in: tickets))
        #expect(keys(sent) == ["TB-1", "TB-4", "TB-2", "TB-3"])
        #expect(sent[1].state == .queued)
        #expect(sent[1].note == "Use the brand blue")
        #expect(TicketQueue.next(in: login, of: sent, autoStart: true, startedByHand: [])?.key == "TB-4")
        // Only a ticket in review or blocked goes back.
        #expect(TicketQueue.sendingBack("TB-2", note: "", in: tickets) == nil)
    }

    @Test func aSentBackTicketWithNoQueueBehindItStaysWhereItWas() throws {
        let tickets = [ticket(1, .blocked), ticket(2, .done)]
        let sent = try #require(TicketQueue.sendingBack("TB-1", note: "Key's in .env now", in: tickets))
        #expect(keys(sent) == ["TB-1", "TB-2"])
    }

    @Test func assigningMovesATicketToTheBackOfTheOtherFeaturesQueue() throws {
        let tickets = [ticket(1, .queued, in: onboarding), ticket(2, .blocked), ticket(3, .queued, in: onboarding)]
        let assigned = try #require(TicketQueue.assigning("TB-2", to: onboarding, in: tickets))
        #expect(keys(assigned) == ["TB-1", "TB-3", "TB-2"])
        #expect(assigned[2].zone == onboarding)
        #expect(assigned[2].state == .queued)
        #expect(TicketQueue.assigning("TB-2", to: onboarding, in: assigned) == nil)
    }

    @Test func aTicketMovedToDoneGoesLast() {
        let tickets = [ticket(1, .review), ticket(2), ticket(3, .done)]
        let done = TicketQueue.updating(tickets[0].moved(to: .done), in: tickets)
        #expect(keys(done) == ["TB-2", "TB-3", "TB-1"])
        // Any other change stays where it is.
        var renamed = tickets[1]
        renamed.summary = "Renamed"
        #expect(keys(TicketQueue.updating(renamed, in: tickets)) == ["TB-1", "TB-2", "TB-3"])
    }

    @Test func onlyAnAgentInTheTicketsFeatureMayReportOnIt() throws {
        let tickets = [ticket(1, .working)]
        let review = TicketReport.review(key: "TB-1", note: "Added the button")
        #expect(apply(review, from: .agent(domain: onboarding), to: tickets) == nil)
        #expect(apply(review, from: .manager(project: project), to: tickets) == nil)
        #expect(apply(review, from: .agent(domain: login), to: [ticket(1)]) == nil)
        let blocked = try #require(apply(
            .blocked(key: "TB-1", reason: "Needs GOOGLE_CLIENT_ID"), from: .agent(domain: login), to: tickets))
        #expect(blocked[0].state == .blocked)
        #expect(blocked[0].note == "Needs GOOGLE_CLIENT_ID")
    }

    @Test func aRepeatedReportChangesNothing() throws {
        let review = TicketReport.review(key: "TB-1", note: "Added the button")
        let once = try #require(apply(review, from: .agent(domain: login), to: [ticket(1, .working)]))
        #expect(apply(review, from: .agent(domain: login), to: once) == nil)
        #expect(apply(.review(key: "TB-9", note: ""), from: .agent(domain: login), to: once) == nil)
    }

    @Test func theManagerAddsATicketToTheBackOfTheFeatureItNames() throws {
        var zones: [UUID] = []
        let tickets = [ticket(1), ticket(2, .queued, in: onboarding)]
        let added = try #require(TicketQueue.applying(
            .add(feature: " login ", summary: "Continue with Google", details: "At /auth/google"),
            from: .manager(project: project), to: tickets, in: textberry, newKey: { zone in
                zones.append(zone)
                return "TB-3"
            }))
        #expect(keys(added) == ["TB-1", "TB-2", "TB-3"])
        #expect(added[2].zone == login)
        #expect(added[2].state == .queued)
        #expect(added[2].summary == "Continue with Google")
        #expect(added[2].details == "At /auth/google")
        #expect(zones == [login])
        #expect(TicketQueue.next(in: login, of: added, autoStart: true, startedByHand: [])?.key == "TB-1")
    }

    @Test func anAddForAFeatureThatIsntThereWaitsInToAssignWithANote() throws {
        let added = try #require(apply(.add(feature: "Billing", summary: "Invoices", details: ""), from: .manager(project: project), to: []))
        #expect(added[0].zone == project)
        #expect(added[0].note == "No feature named Billing in Textberry, so it waits here.")
        let assigned = try #require(apply(.assign(key: "TB-20", feature: "Login"), from: .manager(project: project), to: added))
        #expect(assigned[0].zone == login)
        #expect(assigned[0].note == nil)
    }

    @Test func onlyTheManagerAddsAndAssignsAndOnlyQueuedTicketsInItsProject() throws {
        let add = TicketReport.add(feature: "Login", summary: "Continue with Google", details: "")
        #expect(apply(add, from: .agent(domain: login), to: []) == nil)
        #expect(apply(add, from: .manager(project: login), to: []) == nil)
        let tickets = [ticket(1), ticket(2, .working), ticket(3, .queued, in: UUID())]
        let manager = TicketActor.manager(project: project)
        #expect(apply(.assign(key: "TB-1", feature: "Onboarding"), from: .agent(domain: login), to: tickets) == nil)
        #expect(apply(.assign(key: "TB-2", feature: "Onboarding"), from: manager, to: tickets) == nil)
        #expect(apply(.assign(key: "TB-3", feature: "Onboarding"), from: manager, to: tickets) == nil)
        #expect(apply(.assign(key: "TB-1", feature: "Billing"), from: manager, to: tickets) == nil)
        #expect(apply(.assign(key: "TB-1", feature: "Login"), from: manager, to: tickets) == nil)
        let assigned = try #require(apply(.assign(key: "TB-1", feature: "onboarding"), from: manager, to: tickets))
        #expect(keys(assigned) == ["TB-2", "TB-3", "TB-1"])
        #expect(assigned[2].zone == onboarding)
    }

    @Test func aReportIsReadFromItsArguments() {
        #expect(TicketReport(json: #"["review","tb-7"," Added the button "]"#) == .review(key: "TB-7", note: "Added the button"))
        #expect(TicketReport(json: #"["blocked","TB-7","Needs a key"]"#) == .blocked(key: "TB-7", reason: "Needs a key"))
        #expect(TicketReport(json: #"["review","TB-7"]"#) == nil)
        #expect(TicketReport(json: #"["review"," ","Done"]"#) == nil)
        #expect(TicketReport(json: #"["done","TB-7","Done"]"#) == nil)
        #expect(TicketReport(json: "review TB-7 Done") == nil)
        #expect(TicketReport(json: #"["add","Main app","Settings page"]"#)
            == .add(feature: "Main app", summary: "Settings page", details: ""))
        #expect(TicketReport(json: #"["add","Login","Google button","At /auth/google"]"#)
            == .add(feature: "Login", summary: "Google button", details: "At /auth/google"))
        #expect(TicketReport(json: #"["add","Login"," "]"#) == nil)
        #expect(TicketReport(json: #"["assign","tb-7","Login"]"#) == .assign(key: "TB-7", feature: "Login"))
        #expect(TicketReport(json: #"["assign","TB-7"," "]"#) == nil)
        #expect(TicketReport(json: #"["list"]"#) == nil)
    }

    /// The value src/cli/ticket.zig's test expects `+ticket` to send.
    @Test func aReportReadsWhatTheCLISends() {
        let sent = #"["review","TB-7","Added the \"Continue\" button\nand the callback"]"#
        #expect(TicketReport(json: sent) == .review(key: "TB-7", note: "Added the \"Continue\" button\nand the callback"))
    }

    @Test func aPaneIsItsDomainsAgentOrItsProjectsManager() {
        var model = CanvasModel()
        model.addZone(CanvasZone(id: project, frame: CGRect(x: 0, y: 0, width: 4000, height: 2000)))
        model.addZone(CanvasZone(id: login, frame: CGRect(x: 100, y: 100, width: 1000, height: 1000), parent: project))
        let agent = UUID(), manager = UUID(), outside = UUID(), loose = UUID()
        var panes = CanvasPaneZones()
        panes.zones = [agent: login, manager: login, loose: project]
        panes.panes = [agent, manager, loose, outside]
        model.updateZone(project) { $0.manager = manager }
        #expect(model.ticketRole(of: agent, panes: panes) == .agent(domain: login))
        #expect(model.ticketRole(of: manager, panes: panes) == .manager(project: project))
        #expect(model.ticketRole(of: loose, panes: panes) == nil)
        #expect(model.ticketRole(of: outside, panes: panes) == nil)
    }
}
#endif
