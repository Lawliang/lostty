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

    @Test func aDomainWinsOverItsProject() {
        var model = CanvasModel()
        model.addZone(zone(project, CGRect(x: 0, y: 0, width: 2000, height: 1000)))
        model.addZone(zone(domain, CGRect(x: 100, y: 100, width: 800, height: 600), in: project))
        #expect(model.zone(for: CGRect(x: 100, y: 100, width: 400, height: 300)) == domain)
        #expect(model.zone(for: CGRect(x: 1200, y: 300, width: 400, height: 300)) == project)
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
        model.removeZone(project)
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
        let around = model.zoneAround([a, b])
        #expect(around?.frame == CGRect(x: 60, y: 60, width: 980, height: 380))
        #expect(around?.parent == project)
        // Clipped to the project's bottom edge.
        #expect(model.zoneAround([c])?.frame == CGRect(x: 1460, y: 760, width: 480, height: 240))
    }

    @Test func aZoneFromTheCardsOfAZoneJustMadeIsRefused() {
        var model = CanvasModel()
        model.add(a, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let around = model.zoneAround([a])
        let added = around.map { model.addZone(zone(project, $0.frame)) }
        #expect(added == true)
        // The domain it offers would be the project itself.
        #expect(model.zoneAround([a]) == nil)
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
}
#endif
