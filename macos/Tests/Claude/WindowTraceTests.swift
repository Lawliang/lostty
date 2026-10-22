#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Lostty

struct WindowTraceTests {
    private let a = UUID()
    private let since = Date(timeIntervalSinceReferenceDate: 0)

    private func skin(_ accent: String, _ accent2: String? = nil) -> Skin {
        var skin = Skin(name: accent, background: RGB(hex: "#101820")!, foreground: nil,
                        accent: RGB(hex: accent)!, texture: .none, textureOpacity: 0.16)
        skin.accent2 = accent2.flatMap(RGB.init(hex:))
        return skin
    }

    private func lighting(_ phase: TracePhase, skin: Skin? = nil, enabled: Bool = true) -> WindowTrace.Lighting? {
        WindowTrace.lighting(pane: a, phase: phase, skin: skin, enabled: enabled)
    }

    @Test func darkWhileNothingWorks() {
        #expect(lighting(.off) == nil)
    }

    @Test func claudeWorkingLightsThePane() {
        #expect(lighting(.racing(since: since))?.pane == a)
    }

    @Test func onlySubagentsWorkingLeavesItDark() {
        // The pane keeps their bottom glow instead.
        #expect(lighting(.racing(since: since, subagents: true)) == nil)
    }

    @Test func aPaneWithNoSkinGetsTheWebsitesPinkAndCyan() {
        let lit = lighting(.racing(since: since))
        #expect(lit?.primary == RGB(hex: "#ff3df2")!)
        #expect(lit?.secondary == RGB(hex: "#28e7ff")!)
    }

    @Test func aSkinnedPaneUsesItsTraceColors() {
        let lit = lighting(.racing(since: since), skin: skin("#46a2ff", "#ffd23d"))
        #expect(lit?.primary == RGB(hex: "#46a2ff")!)
        #expect(lit?.secondary == RGB(hex: "#ffd23d")!)
    }

    @Test func aPaneWithItsTraceOffStaysDark() {
        var off = skin("#46a2ff")
        off.trace = SkinTrace(disabled: true)
        #expect(lighting(.racing(since: since), skin: off) == nil)
        #expect(lighting(.racing(since: since), enabled: false) == nil)
    }

    @Test func aSkinnedPaneRunsAtItsTracesSpeed() {
        var fast = skin("#46a2ff")
        fast.trace = SkinTrace(speed: 2)
        #expect(lighting(.racing(since: since), skin: fast)?.speed == 2)
        #expect(lighting(.racing(since: since))?.since == since)
    }

    private let rect = CGRect(x: 0, y: 0, width: 100, height: 50)

    private func head(_ elapsed: Double, route: TraceRoute = .all, speed: Double = 1,
                      journey: TraceOverlay.Journey = .init()) -> (point: CGPoint, clockwise: Bool) {
        WindowTrace.head(journey, since: since, in: rect, elapsed: elapsed, route: route, speed: speed)
    }

    @Test func theHeadEasesCornerToCornerAsTheSkinTraceDoes() {
        // A leg takes 0.6s at speed 1: at rest leaving the corner, halfway
        // at half the time, at rest again on the next corner.
        #expect(head(0).point == CGPoint(x: 0, y: 0))
        #expect(abs(head(0.15).point.x - 100 * (1 - cos(.pi / 4)) / 2) < 1e-9)
        #expect(abs(head(0.3).point.x - 50) < 1e-9)
        #expect(head(0.6).point == CGPoint(x: 100, y: 0))
        #expect(abs(head(0.9).point.y - 25) < 1e-9)
        #expect(head(0.9).clockwise)
        // Twice the speed, half the time.
        #expect(abs(head(0.15, speed: 2).point.x - 50) < 1e-9)
    }

    @Test func theHeadIsWhereTheSkinTracesHeadIs() {
        let journey = TraceOverlay.Journey()
        var motion = TraceMotion()
        for elapsed in stride(from: 0.0, through: 7.3, by: 0.37) {
            motion.advance(to: elapsed, course: .route(.all), legSeconds: TraceFrame.legSeconds(speed: 1.3))
            let skin = motion.path(in: rect, at: elapsed, legSeconds: TraceFrame.legSeconds(speed: 1.3)).sample(at: 1)
            let point = head(elapsed, speed: 1.3, journey: journey).point
            #expect(hypot(point.x - skin.point.x, point.y - skin.point.y) < 1e-9)
        }
    }

    @Test func onASideRouteTheHeadTurnsBack() {
        // Right Only: down the right side, then back up it.
        #expect(head(0.3, route: .right).clockwise)
        #expect(abs(head(0.3, route: .right).point.y - 25) < 1e-9)
        #expect(!head(0.9, route: .right).clockwise)
    }

    @Test func theGradientsTipPointsAtTheHead() {
        let center = CGPoint(x: 50, y: 25)
        for point in [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 10), CGPoint(x: 0, y: 50)] {
            for clockwise in [true, false] {
                let turn = WindowTrace.turn(toward: point, from: center, clockwise: clockwise)
                let tip = clockwise ? 0.95 : 0.05
                let bearing = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
                let off = (-90 + tip * 360 + turn - Double(bearing)).truncatingRemainder(dividingBy: 360)
                #expect(min(abs(off), 360 - abs(off)) < 1e-9)
                #expect((0..<360).contains(turn))
            }
        }
    }

    @Test func gradientMatchesTheWebsiteWithTheTipALighterHead() {
        #expect(WindowTrace.stopLocations == [0, 0.64, 0.80, 0.93, 0.95, 0.96, 1])
        let colors = TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan)
        let stops = WindowTrace.stops(colors)
        #expect(stops.map { Double($0.location) } == WindowTrace.stopLocations)
        #expect(stops[3].color == TraceColors.color(WindowTrace.websitePink))
        // The tip: the head's pink lightened a little, not white.
        let tip = TraceColors.color(WindowTrace.websitePink.mixed(with: .white, amount: 0.35))
        #expect(stops[4].color == tip)
        #expect(stops[4].color != stops[3].color)
        #expect(!stops.contains { $0.color == .white })
    }

    @Test func runningCounterclockwiseTheGradientIsMirrored() {
        let colors = TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan)
        let stops = WindowTrace.stops(colors, clockwise: false)
        let locations = stops.map { Double($0.location) }
        #expect(locations == locations.sorted())
        #expect(zip(locations, [0, 0.04, 0.05, 0.07, 0.2, 0.36, 1]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(stops[2].color == WindowTrace.tip(colors))
        #expect(stops[3].color == TraceColors.color(WindowTrace.websitePink))
    }
}

struct CanvasZoomCompensationTests {
    @Test func zoomedOutATraceKeepsItsWidthOnScreen() {
        #expect(CanvasZoomCompensation.scale(zoom: 1) == 1)
        #expect(CanvasZoomCompensation.scale(zoom: 0.5) == 2)
        #expect(CanvasZoomCompensation.scale(zoom: 0.25) == 4)
        #expect(CanvasZoomCompensation.scale(zoom: 2) == 1)
        #expect(CanvasZoomCompensation.scale(zoom: 0) == 1)
    }
}

struct ReadyOverlayTests {
    @Test func theLineMatchesOneTerminalRow() {
        #expect(ClaudeReadyOverlay.fontSize(cellHeight: 18) == 15)
        #expect(ClaudeReadyOverlay.fontSize(cellHeight: 0) == 13)
    }
}

struct TraceStyleTests {
    private func freshDefaults() -> UserDefaults {
        let name = "TraceStyleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func newLosttyKeepsSkinTraces() {
        #expect(TraceStyle.current(in: freshDefaults()) == .skin)
    }

    @Test func savedStyleIsRemembered() {
        let defaults = freshDefaults()
        for style in TraceStyle.allCases {
            TraceStyle.save(style, in: defaults)
            #expect(TraceStyle.current(in: defaults) == style)
        }
        defaults.set("rainbow", forKey: TraceStyle.defaultsKey)
        #expect(TraceStyle.current(in: defaults) == .skin)
    }

    @Test func menuOffersSkinTracesWithAndWithoutTheGlowThenWindowLight() {
        #expect(TraceStyle.allCases.map(\.title) == ["Skin Traces", "Skin Traces, No Head Glow", "Window Light"])
    }

    @Test func onlySubagentsWorkingIsSubagentsOnly() {
        #expect(TracePhase.racing(since: Date(), subagents: true).subagentsOnly)
        #expect(!TracePhase.racing(since: Date()).subagentsOnly)
        #expect(!TracePhase.off.subagentsOnly)
    }
}
#endif
