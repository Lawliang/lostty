#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct CanvasZoneAgentsTests {
    private let project = UUID(), domain = UUID(), card = UUID(), other = UUID()
    private let p1 = UUID(), p2 = UUID(), p3 = UUID()

    private func textberry(projectBrief: String = "An SMS app.", domainBrief: String = "Sign-up flow.") -> CanvasModel {
        var model = CanvasModel()
        model.addZone(CanvasZone(
            id: project, frame: CGRect(x: 0, y: 0, width: 2000, height: 1000), name: "Textberry",
            folder: "~/projectrepos/textberry", brief: projectBrief))
        model.addZone(CanvasZone(
            id: domain, frame: CGRect(x: 100, y: 100, width: 800, height: 600), name: "Onboarding",
            parent: project, folder: "onboarding", brief: domainBrief))
        return model
    }

    @Test func aDomainsBriefNamesItsZoneFolderAndBothBriefs() {
        #expect(textberry().zoneStart(domain) == """
            Lostty zone: Textberry › Onboarding (~/projectrepos/textberry/onboarding).
            Textberry: An SMS app.
            Onboarding: Sign-up flow.
            """)
    }

    @Test func aBriefLeavesOutEmptyBriefsAndAMissingFolder() {
        var model = textberry(projectBrief: "  ", domainBrief: "Sign-up flow.")
        #expect(model.zoneStart(project) == "Lostty zone: Textberry (~/projectrepos/textberry).")
        model.updateZone(project) { $0.folder = nil }
        #expect(model.zoneStart(domain) == "Lostty zone: Textberry › Onboarding.\nOnboarding: Sign-up flow.")
        #expect(model.zoneStart(UUID()) == nil)
    }

    @Test func movingInGivesTheBriefsAndMovingOutNamesTheZoneLeft() {
        let model = textberry()
        #expect(model.zoneMovedIn(domain) == """
            You're now in zone Textberry › Onboarding.
            Textberry: An SMS app.
            Onboarding: Sign-up flow.
            """)
        #expect(CanvasModel.zoneMovedOut(of: "Textberry") == "You've left zone Textberry.")
    }

    @Test func theOwnerHearsOfAPaneOnlyWhenItLeavesItsProject() {
        let before = textberry()
        var after = before
        let elsewhere = UUID()
        after.addZone(CanvasZone(id: elsewhere, frame: CGRect(x: 3000, y: 0, width: 2000, height: 1000)))
        let pane = UUID()
        func move(_ from: UUID?, _ to: UUID?) -> CanvasPaneZones.Move { .init(pane: pane, from: from, to: to) }
        #expect(!after.leftProject(move(project, domain), before: before))
        #expect(!after.leftProject(move(domain, project), before: before))
        #expect(!after.leftProject(move(nil, project), before: before))
        #expect(after.leftProject(move(domain, nil), before: before))
        #expect(after.leftProject(move(project, elsewhere), before: before))
        after.removeZone(domain)
        #expect(!after.leftProject(move(domain, nil), before: before))
    }

    @Test func aNoticeShortensALongCardTitle() {
        #expect(CanvasModel.noticeTitle("claude") == "claude")
        let forty = String(repeating: "a", count: 40)
        #expect(CanvasModel.noticeTitle(forty) == forty)
        #expect(CanvasModel.noticeTitle("clear; claude -p 'Call SendMessage exactly once to lostty-27'")
            == "clear; claude -p 'Call SendMessage exac…")
    }

    @Test func aCardsPanesShareItsZone() {
        var model = textberry()
        model.add(card, frame: CGRect(x: 200, y: 200, width: 400, height: 300))
        model.add(other, frame: CGRect(x: 3000, y: 3000, width: 400, height: 300))
        let zones = model.paneZones([(card, [p1, p2]), (other, [p3])])
        #expect(zones.panes == [p1, p2, p3])
        #expect(zones.zones == [p1: domain, p2: domain])
    }

    @Test func onlyAPaneThatStaysOnTheCanvasAndChangesZoneMoves() {
        let before = CanvasPaneZones(panes: [p1, p2, p3], zones: [p1: domain, p2: domain])
        let new = UUID()
        let after = CanvasPaneZones(panes: [p1, p3, new], zones: [p1: project, p3: domain, new: domain])
        let expected = [
            CanvasPaneZones.Move(pane: p1, from: domain, to: project),
            CanvasPaneZones.Move(pane: p3, from: nil, to: domain),
        ].sorted { $0.pane.uuidString < $1.pane.uuidString }
        #expect(before.moves(to: after) == expected)
        #expect(after.moves(to: CanvasPaneZones(panes: [p1, p3, new], zones: [p1: project, new: domain]))
            == [CanvasPaneZones.Move(pane: p3, from: domain, to: nil)])
        #expect(before.moves(to: before).isEmpty)
    }

    @Test func aZoneFilesMembersAreItsProjectsTmuxSessions() throws {
        var model = textberry()
        let elsewhere = UUID(), p4 = UUID(), p5 = UUID()
        model.addZone(CanvasZone(id: elsewhere, frame: CGRect(x: 5000, y: 0, width: 1000, height: 1000), name: "Lostty"))
        let panes = CanvasPaneZones(
            panes: [p1, p2, p3, p4, p5], zones: [p1: domain, p2: project, p3: elsewhere, p4: domain, p5: project])
        let sessions = [p1: "tb-onboarding", p2: "tb-api", p3: "lostty", p5: "tb-api"]
        let file = try #require(model.zoneFile(domain, panes: panes, sessions: sessions))
        #expect(file.zone == "Textberry › Onboarding")
        #expect(file.members == ["tb-api", "tb-onboarding"])
        #expect(model.zoneFile(project, panes: panes, sessions: sessions)?.members == ["tb-api", "tb-onboarding"])
        #expect(model.zoneFile(elsewhere, panes: panes, sessions: sessions)?.members == ["lostty"])
        #expect(model.zoneFile(domain, panes: panes, sessions: [:])?.members == [])
    }

    @Test func theZoneFileIsJSONTheHooksReadAndNotAHandoffState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = ContextHandoffStore(root: root)
        let store = CanvasZoneStore(panes: handoff.panes)
        let pane = UUID()
        store.writeZone(pane, CanvasZoneFile(
            start: "Lostty zone: Textberry.", zone: "Textberry", folder: nil, members: ["tb-1", "tb-2"]))
        store.replaceSay(pane, "You've left zone Onboarding.")
        store.replaceSay(pane, "You're now in zone Textberry.")
        store.writeAllow(pane, target: "lostty-a9")

        let url = handoff.panes.appendingPathComponent("\(pane.uuidString).zone.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["start"] as? String == "Lostty zone: Textberry.")
        #expect(json["zone"] as? String == "Textberry")
        #expect(json["folder"] is NSNull)
        #expect(json["members"] as? [String] == ["tb-1", "tb-2"])
        let allow = handoff.panes.appendingPathComponent("\(pane.uuidString).zone.allow")
        #expect(try String(contentsOf: allow, encoding: .utf8) == "lostty-a9")
        let say = handoff.panes.appendingPathComponent("\(pane.uuidString).zone.say")
        #expect(try String(contentsOf: say, encoding: .utf8) == "You're now in zone Textberry.")
        store.appendSay(pane, "You may retry your message to lostty-a9 once.")
        #expect(try String(contentsOf: say, encoding: .utf8)
            == "You're now in zone Textberry.\n\nYou may retry your message to lostty-a9 once.")
        #expect(handoff.loadStates().isEmpty)

        store.removeZone(pane)
        store.removeSay(pane)
        #expect(try FileManager.default.contentsOfDirectory(atPath: handoff.panes.path).isEmpty)
    }
}
#endif
