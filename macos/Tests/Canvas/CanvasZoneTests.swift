#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct CanvasZoneTests {
    private let project = UUID(), other = UUID(), domain = UUID(), sibling = UUID()
    private let a = UUID(), b = UUID(), c = UUID()

    private func zone(_ id: UUID, _ frame: CGRect, in parent: UUID? = nil) -> CanvasZone {
        CanvasZone(id: id, frame: frame, parent: parent)
    }

    @Test func aCardIsInTheZoneHoldingItsCentre() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        #expect(model.zone(for: CGRect(x: 100, y: 100, width: 400, height: 300)) == project)
        // Hanging out past the edge, centre (1900, 500) still inside.
        #expect(model.zone(for: CGRect(x: 1700, y: 350, width: 400, height: 300)) == project)
        // Partly inside, centre (2050, 500) outside.
        #expect(model.zone(for: CGRect(x: 1800, y: 350, width: 500, height: 300)) == nil)
    }

    @Test func aCardBesideOneInAZoneStaysInTheZone() {
        let d = UUID()
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.add(a, frame: CGRect(x: 700, y: 500, width: 600, height: 400))
        model.add(b, frame: CGRect(x: 1300, y: 500, width: 600, height: 400))
        // Right is taken and below leaves the zone: left.
        #expect(model.placement(beside: a) == CGRect(x: 100, y: 500, width: 600, height: 400))
        model.add(c, frame: CGRect(x: 100, y: 500, width: 600, height: 400))
        #expect(model.placement(beside: a) == CGRect(x: 700, y: 100, width: 600, height: 400))
        // No side inside the zone is free: below, as outside zones.
        model.add(d, frame: CGRect(x: 700, y: 100, width: 600, height: 400))
        #expect(model.placement(beside: a) == CGRect(x: 700, y: 900, width: 600, height: 400))
    }

    @Test func aCardBesideOneInAZoneStartsInItsZoneOrTheSourcesZone() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(other, CGRect(x: 0, y: 2000, width: 2000, height: 1000)))
        model.add(a, frame: CGRect(x: 700, y: 500, width: 600, height: 400))
        model.add(b, frame: CGRect(x: 5000, y: 5000, width: 600, height: 400))
        #expect(model.startZone(beside: a, at: CGRect(x: 700, y: 900, width: 600, height: 400)) == project)
        #expect(model.startZone(beside: a, at: CGRect(x: 100, y: 2100, width: 600, height: 400)) == other)
        #expect(model.startZone(beside: b, at: CGRect(x: 5600, y: 5000, width: 600, height: 400)) == nil)
    }

    @Test func aDomainWinsOverItsProject() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project))
        #expect(model.zone(for: CGRect(x: 100, y: 100, width: 400, height: 300)) == domain)
        #expect(model.zone(for: CGRect(x: 1200, y: 300, width: 400, height: 300)) == project)
    }

    @Test func savedZonesComeBackWithADomainListedBeforeItsProject() {
        var model = CanvasModel()
        let saved = [
            zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project),
            zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)),
        ]
        model.addZones(saved)
        #expect(Set(model.zones.map(\.id)) == [project, domain])
        #expect(model.zone(for: CGRect(x: 100, y: 100, width: 400, height: 300)) == domain)
    }

    @Test func aZoneStaysInTheDocumentAndAtLeastACardsMinimumSize() {
        var model = CanvasModel()
        let offTheEdge = model.addZone(zone(project, CGRect(x: -10, y: 0, width: 1000, height: 1000)))
        let tooNarrow = model.addZone(zone(project, CGRect(x: 0, y: 0, width: 300, height: 1000)))
        #expect(!offTheEdge)
        #expect(!tooNarrow)
        #expect(model.zones.isEmpty)
    }

    @Test func projectsCantBeDrawnOrMovedOverEachOther() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 1000, height: 1000)))
        let over = model.addZone(zone(other, CGRect(x: 500, y: 500, width: 1000, height: 1000)))
        let alongside = model.addZone(zone(other, CGRect(x: 1000, y: 0, width: 1000, height: 1000)))
        let movedOver = model.moveZone(other, by: CGSize(width: -100, height: 0))
        #expect(!over)
        #expect(alongside)
        #expect(movedOver == nil)
        #expect(model.zone(other)?.frame == CGRect(x: 1000, y: 0, width: 1000, height: 1000))
    }

    @Test func aDomainStaysInsideItsProjectAndOffItsSiblings() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        let inside = model.addZone(zone(domain, CGRect(x: 0, y: 0, width: 1000, height: 1000), in: project))
        let overSibling = model.addZone(zone(sibling, CGRect(x: 900, y: 0, width: 600, height: 600), in: project))
        let pastProject = model.addZone(zone(sibling, CGRect(x: 1000, y: 0, width: 1200, height: 600), in: project))
        let beside = model.addZone(zone(sibling, CGRect(x: 1000, y: 0, width: 1000, height: 600), in: project))
        let movedOut = model.moveZone(sibling, by: CGSize(width: 100, height: 0))
        let movedOver = model.moveZone(sibling, by: CGSize(width: -100, height: 0))
        // No third level, and no domain without its project.
        let thirdLevel = model.addZone(zone(other, CGRect(x: 100, y: 100, width: 400, height: 300), in: domain))
        let orphan = model.addZone(zone(other, CGRect(x: 5000, y: 0, width: 400, height: 300), in: UUID()))
        #expect(inside)
        #expect(!overSibling)
        #expect(!pastProject)
        #expect(beside)
        #expect(movedOut == nil)
        #expect(movedOver == nil)
        #expect(model.zone(sibling)?.frame == CGRect(x: 1000, y: 0, width: 1000, height: 600))
        #expect(!thirdLevel)
        #expect(!orphan)
    }

    @Test func aProjectCantShrinkPastItsDomains() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 1000, y: 0, width: 800, height: 600), in: project))
        let pastDomain = model.setZoneFrame(CGRect(x: 0, y: 0, width: 1500, height: 1000), of: project)
        #expect(!pastDomain)
        #expect(model.zone(project)?.frame == CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let toDomain = model.setZoneFrame(CGRect(x: 0, y: 0, width: 1800, height: 600), of: project)
        #expect(toDomain)
    }

    @Test func aDomainCantGrowPastItsProjectOrIntoASibling() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 1000, y: 0, width: 800, height: 600), in: project))
        model.addZone(zone(sibling, CGRect(x: 0, y: 0, width: 800, height: 600), in: project))
        let pastProject = model.setZoneFrame(CGRect(x: 1000, y: 0, width: 1200, height: 600), of: domain)
        let intoSibling = model.setZoneFrame(CGRect(x: 700, y: 0, width: 1100, height: 600), of: domain)
        let toTheEdges = model.setZoneFrame(CGRect(x: 800, y: 0, width: 1200, height: 1000), of: domain)
        #expect(!pastProject)
        #expect(!intoSibling)
        #expect(toTheEdges)
    }

    @Test func movingAProjectMovesItsDomainsAndCards() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 0, y: 0, width: 800, height: 600), in: project))
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        model.add(b, frame: CGRect(x: 1200, y: 200, width: 400, height: 300))
        model.add(c, frame: CGRect(x: 3000, y: 0, width: 400, height: 300))
        let movedWithProject = model.moveZone(project, by: CGSize(width: 100, height: 200))
        #expect(movedWithProject == [a, b])
        #expect(model.zone(project)?.frame == CGRect(x: 100, y: 200, width: 2000, height: 1000))
        #expect(model.zone(domain)?.frame == CGRect(x: 100, y: 200, width: 800, height: 600))
        #expect(model.card(a)?.frame == CGRect(x: 200, y: 300, width: 400, height: 300))
        #expect(model.card(b)?.frame == CGRect(x: 1300, y: 400, width: 400, height: 300))
        #expect(model.card(c)?.frame == CGRect(x: 3000, y: 0, width: 400, height: 300))
        // A domain takes only its own cards.
        let movedWithDomain = model.moveZone(domain, by: CGSize(width: 100, height: 0))
        #expect(movedWithDomain == [a])
        #expect(model.card(a)?.frame == CGRect(x: 300, y: 300, width: 400, height: 300))
        #expect(model.card(b)?.frame == CGRect(x: 1300, y: 400, width: 400, height: 300))
    }

    @Test func removingAZoneRemovesItsDomainsAndKeepsCards() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 0, y: 0, width: 800, height: 600), in: project))
        model.addZone(zone(other, CGRect(x: 3000, y: 0, width: 1000, height: 1000)))
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(model.removeZone(project) == [project, domain])
        #expect(model.zones.map(\.id) == [other])
        #expect(model.card(a)?.frame == CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(model.zone(for: CGRect(x: 100, y: 100, width: 400, height: 300)) == nil)
    }

    @Test func aZoneFromCardsInAProjectIsADomainOfIt() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        model.add(b, frame: CGRect(x: 600, y: 100, width: 400, height: 300))
        model.add(c, frame: CGRect(x: 1500, y: 800, width: 400, height: 300))
        let d = UUID()
        model.add(d, frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let around = model.zoneAround([a, b])
        #expect(around?.frame == CGRect(x: 60, y: 60, width: 980, height: 380))
        #expect(around?.parent == project)
        // Clipped 12 inside the project's bottom edge.
        #expect(model.zoneAround([c])?.frame == CGRect(x: 1460, y: 760, width: 480, height: 228))
        // Clipped 12 inside its left edge and 48 below its top, clear of its label.
        #expect(model.zoneAround([d])?.frame == CGRect(x: 12, y: 48, width: 428, height: 292))
    }

    @Test func aZoneFromTheCardsOfAZoneJustMadeIsADomainBelowItsLabel() {
        var model = CanvasModel()
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let around = model.zoneAround([a])
        let added = around.map { model.addZone(zone(project, $0.frame)) }
        #expect(added == true)
        // The project is (60, 60, 480, 380).
        let domain = model.zoneAround([a])
        #expect(domain?.frame == CGRect(x: 72, y: 108, width: 456, height: 320))
        #expect(domain?.parent == project)
    }

    @Test func aZoneFromCardsOutsideZonesIsAProject() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.add(a, frame: CGRect(x: 3000, y: 0, width: 400, height: 300))
        model.add(b, frame: CGRect(x: 3500, y: 500, width: 400, height: 300))
        let around = model.zoneAround([a, b])
        // Clipped to the document's top edge.
        #expect(around?.frame == CGRect(x: 2960, y: 0, width: 980, height: 840))
        #expect(around.map { $0.parent == nil } == true)
    }

    @Test func aZoneFromCardsOverAnotherZoneIsRefused() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        model.add(b, frame: CGRect(x: 3000, y: 0, width: 400, height: 300))
        #expect(model.zoneAround([a, b]) == nil)
        #expect(model.zoneAround([]) == nil)
    }

    @Test func nextColorNeverRepeatsInsideAProject() {
        var model = CanvasModel()
        #expect(model.nextColor(parent: nil) == .blue)
        model.addZone(CanvasZone(id: project, frame: CGRect(x: 0, y: 0, width: 8000, height: 1000), color: .blue))
        #expect(model.nextColor(parent: nil) == .green)
        model.addZone(CanvasZone(id: other, frame: CGRect(x: 0, y: 2000, width: 1000, height: 1000), color: .green))
        // Another project's green is free for a domain.
        #expect(model.nextColor(parent: project) == .green)
        for index in 0..<7 {
            let color = model.nextColor(parent: project)
            let frame = CGRect(x: CGFloat(index) * 1000, y: 0, width: 1000, height: 1000)
            let added = model.addZone(CanvasZone(id: UUID(), frame: frame, color: color, parent: project))
            #expect(added)
        }
        let colors = model.zones.filter { $0.id == project || $0.parent == project }.map(\.color)
        #expect(Set(colors).count == CanvasZone.Color.allCases.count)
        // All eight taken: round again from the first.
        #expect(model.nextColor(parent: project) == .blue)
    }

    @Test func aNewZoneIsNamedAndColoredForWhereItGoes() {
        var model = CanvasModel()
        let first = model.newZone(CGRect(x: 0, y: 0, width: 4000, height: 2000), parent: nil)
        #expect(first.name == "Zone 1")
        #expect(first.color == .blue)
        #expect(first.parent == nil)
        model.addZone(first)
        let inside = model.newZone(CGRect(x: 100, y: 100, width: 800, height: 600), parent: first.id)
        #expect(inside.name == "Domain 2")
        #expect(inside.color == .green)
        #expect(inside.parent == first.id)
        #expect(model.newZone(CGRect(x: 5000, y: 0, width: 800, height: 600), parent: nil).name == "Zone 2")
    }

    @Test func aZoneDrawnWhollyInsideAProjectIsItsDomain() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 4000, height: 2000)))
        model.addZone(zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project))
        #expect(model.project(holding: CGRect(x: 1000, y: 100, width: 800, height: 600)) == project)
        #expect(model.project(holding: CGRect(x: 3500, y: 100, width: 800, height: 600)) == nil)
        #expect(model.project(holding: CGRect(x: 5000, y: 100, width: 800, height: 600)) == nil)
    }

    @Test func draggingAZoneEdgeResizesItAsACardsWould() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 4000, height: 2000)))
        model.addZone(zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project))
        let start = CGRect(x: 0, y: 0, width: 4000, height: 2000)
        let wider = CanvasModel.resized(start, edges: [.right, .bottom], by: CGSize(width: 500, height: 100))
        let grew = model.setZoneFrame(wider, of: project)
        #expect(grew)
        #expect(model.zone(project)?.frame == CGRect(x: 0, y: 0, width: 4500, height: 2100))
        // Shrinking past the domain is refused; the last allowed frame stays.
        let past = CanvasModel.resized(wider, edges: .right, by: CGSize(width: -4000, height: 0))
        let shrank = model.setZoneFrame(past, of: project)
        #expect(!shrank)
        #expect(model.zone(project)?.frame == wider)
    }

    private func projectWithDomain(folder: String?, subfolder: String?) -> CanvasModel {
        var model = CanvasModel()
        var top = zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000))
        top.folder = folder
        var inner = zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project)
        inner.folder = subfolder
        model.addZone(top)
        model.addZone(inner)
        return model
    }

    @Test func aDomainStartsInItsSubfolderOfTheProjectFolder() {
        let model = projectWithDomain(folder: "/Users/me/textberry", subfolder: "apps/onboarding")
        #expect(model.startFolder(ofZone: domain) == "/Users/me/textberry/apps/onboarding")
        #expect(model.startFolder(ofZone: project) == "/Users/me/textberry")
    }

    @Test func aDomainWithoutASubfolderStartsInTheProjectFolder() {
        #expect(projectWithDomain(folder: "/Users/me/textberry", subfolder: nil).startFolder(ofZone: domain)
            == "/Users/me/textberry")
        #expect(projectWithDomain(folder: "/Users/me/textberry", subfolder: " ").startFolder(ofZone: domain)
            == "/Users/me/textberry")
    }

    @Test func noProjectFolderMeansNoStartFolder() {
        let model = projectWithDomain(folder: nil, subfolder: "apps/onboarding")
        #expect(model.startFolder(ofZone: domain) == nil)
        #expect(model.startFolder(ofZone: project) == nil)
        #expect(model.startFolder(ofZone: UUID()) == nil)
    }

    @Test func aTildeInTheProjectFolderIsHome() {
        let model = projectWithDomain(folder: "~/textberry", subfolder: "web")
        let home = NSHomeDirectory()
        #expect(model.startFolder(ofZone: project) == home + "/textberry")
        #expect(model.startFolder(ofZone: domain) == home + "/textberry/web")
    }

    @Test func aSubfolderIsStoredRelativeToItsProjectFolder() {
        #expect(CanvasModel.subfolder("/Users/me/textberry/apps/web", of: "/Users/me/textberry") == "apps/web")
        #expect(CanvasModel.subfolder("/Users/me/textberry", of: "/Users/me/textberry/") == "")
        #expect(CanvasModel.subfolder(NSHomeDirectory() + "/tb/web", of: "~/tb") == "web")
        #expect(CanvasModel.subfolder("/Users/me/textberry-old", of: "/Users/me/textberry") == nil)
        #expect(CanvasModel.subfolder("/Users/me/other", of: "/Users/me/textberry") == nil)
    }

    @Test func updatingAZoneChangesWhatItSaysNotWhereItIs() {
        var model = projectWithDomain(folder: nil, subfolder: nil)
        let renamed = model.updateZone(domain) { zone in
            zone.name = "Onboarding"
            zone.color = .teal
            zone.brief = "Signup and first run."
        }
        #expect(renamed)
        #expect(model.zone(domain)?.name == "Onboarding")
        #expect(model.zone(domain)?.color == .teal)
        #expect(model.zone(domain)?.brief == "Signup and first run.")

        let before = model
        let moved = model.updateZone(domain) { zone in
            zone.name = "Moved"
            zone.frame = CGRect(x: 1500, y: 100, width: 800, height: 600)
        }
        let orphaned = model.updateZone(domain) { $0.parent = nil }
        #expect(!moved)
        #expect(!orphaned)
        #expect(model == before)
    }

    @Test func aProjectsDefaultTicketPrefixIsItsInitials() {
        #expect(CanvasZone.defaultTicketPrefix("Textberry") == "TE")
        #expect(CanvasZone.defaultTicketPrefix("Text Berry") == "TB")
        #expect(CanvasZone.defaultTicketPrefix("TextBerry") == "TB")
        #expect(CanvasZone.defaultTicketPrefix("lostty main") == "LM")
        #expect(CanvasZone.defaultTicketPrefix("my-big-fat-app") == "MBF")
        #expect(CanvasZone.defaultTicketPrefix("") == "LT")
    }

    @Test func aTicketTakesItsProjectsPrefixInAnyOfItsZones() {
        var model = CanvasModel()
        var named = zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000))
        named.name = "Textberry"
        model.addZone(named)
        model.addZone(zone(domain, CGRect(x: 0, y: 0, width: 800, height: 600), in: project))
        #expect(model.ticketPrefix(ofZone: project) == "TE")
        #expect(model.ticketPrefix(ofZone: domain) == "TE")
        #expect(model.ticketPrefix(ofZone: nil) == "LT")
        model.updateZone(project) { $0.keyPrefix = " tb " }
        #expect(model.ticketPrefix(ofZone: domain) == "TB")
    }

    @Test func aPanelListsItsZonesTicketsTaggingADomainsInItsProjects() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 0, y: 0, width: 800, height: 600), in: project))
        model.addZone(zone(other, CGRect(x: 3000, y: 0, width: 1000, height: 1000)))
        #expect(model.ticketZones(shownIn: nil) == nil)
        #expect(model.ticketZones(shownIn: project) == [project, domain])
        #expect(model.ticketZones(shownIn: domain) == [domain])

        let inDomain = CanvasTicket(key: "LT-1", zone: domain), inProject = CanvasTicket(key: "LT-2", zone: project)
        #expect(model.ticketTag(inDomain, shownIn: project)?.id == domain)
        #expect(model.ticketTag(inProject, shownIn: project) == nil)
        #expect(model.ticketTag(inDomain, shownIn: domain) == nil)
        #expect(model.ticketTag(inDomain, shownIn: nil) == nil)
    }

    @Test func aProjectsCaptionCountsItsCardsAndThePanesWorkingAndWaiting() {
        let (p1, p2, p3, p4) = (UUID(), UUID(), UUID(), UUID())
        let caption = CanvasZoneCaption(
            zone(project, .zero),
            folder: NSHomeDirectory() + "/projectrepos/textberry",
            members: [.terminal(panes: [p1, p2]), .terminal(panes: [p3]), .tickets, .tickets, .terminal(panes: [p4])],
            working: [p1, p3, UUID()],
            waiting: [p2])
        #expect(caption.note == "~/projectrepos/textberry")
        #expect(caption.text == "3 terminals · 2 ticket panels · 2 working · 1 waiting")
    }

    @Test func aCaptionSaysOneInTheSingularAndLeavesOutZeros() {
        let pane = UUID()
        let caption = CanvasZoneCaption(
            zone(project, .zero), folder: nil, members: [.terminal(panes: [pane]), .tickets], working: [], waiting: [pane])
        #expect(caption.note == nil)
        #expect(caption.text == "1 terminal · 1 ticket panel · 1 waiting")
    }

    @Test func aPaneWaitingOnYouIsntAlsoCountedWorking() {
        let pane = UUID()
        let caption = CanvasZoneCaption(
            zone(project, .zero), folder: nil, members: [.terminal(panes: [pane])], working: [pane], waiting: [pane])
        #expect(caption.text == "1 terminal · 1 waiting")
    }

    @Test func anEmptyProjectSaysItHasNoTerminals() {
        let caption = CanvasZoneCaption(zone(project, .zero), folder: "/tmp/x", members: [], working: [], waiting: [])
        #expect(caption.text == "0 terminals")
        let panelOnly = CanvasZoneCaption(zone(project, .zero), folder: nil, members: [.tickets], working: [], waiting: [])
        #expect(panelOnly.text == "1 ticket panel")
    }

    @Test func aDomainsCaptionIsTheFirstLineOfItsBrief() {
        var briefed = zone(domain, .zero, in: project)
        briefed.brief = "\n  Phone number, contacts, first text.  \nKeep it short."
        let caption = CanvasZoneCaption(
            briefed, folder: "/tmp/x", members: [.terminal(panes: [UUID()])], working: [], waiting: [])
        #expect(caption.note == "Phone number, contacts, first text.")
        #expect(caption.counts.isEmpty)

        briefed.brief = " \n "
        #expect(CanvasZoneCaption(briefed, folder: nil, members: [], working: [], waiting: []).note == nil)
    }
}
#endif
