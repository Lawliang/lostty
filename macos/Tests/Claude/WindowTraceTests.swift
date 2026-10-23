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

    @Test func onlySubagentsWorkingKeepsItLitAlongTheBottom() {
        let lit = lighting(.racing(since: since, subagents: true))
        #expect(lit?.pane == a)
        #expect(lit?.subagents == true)
        #expect(lighting(.racing(since: since))?.subagents == false)
    }

    @Test func aPaneWithNoSkinGetsTheWebsitesPinkAndCyan() {
        let lit = lighting(.racing(since: since))
        #expect(lit?.primary == RGB(hex: "#ff3df2")!)
        #expect(lit?.secondary == RGB(hex: "#28e7ff")!)
    }

    @Test func theBottomGlowKeepsTheTracesOwnColors() {
        // With no skin, the trace's pink and cyan, not the website's.
        let lit = lighting(.racing(since: since, subagents: true))
        #expect(lit?.glow == ResolvedTrace.unskinnedColor)
        #expect(lit?.glow2 == ResolvedTrace.unskinnedColor2)
        let skinned = lighting(.racing(since: since, subagents: true), skin: skin("#46a2ff", "#ffd23d"))
        #expect(skinned?.glow == RGB(hex: "#46a2ff")!)
        #expect(skinned?.glow2 == RGB(hex: "#ffd23d")!)
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

    private func head(_ elapsed: Double, route: TraceRoute = .all, course: TraceCourse? = nil, speed: Double = 1,
                      journey: TraceOverlay.Journey = .init()) -> (point: CGPoint, clockwise: Bool) {
        WindowTrace.head(journey, since: since, in: rect, elapsed: elapsed, course: course ?? .route(route), speed: speed)
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

    @Test func forSubagentsTheHeadRunsBackAndForthAlongTheBottom() {
        // Right to left along the bottom edge, then back.
        for elapsed in [0.3, 0.9] {
            let point = head(elapsed, course: .subagents).point
            #expect(abs(point.x - 50) < 1e-9 && point.y == 50)
        }
        #expect(head(0.3, course: .subagents).clockwise)
        #expect(!head(0.9, course: .subagents).clockwise)
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
        let shades = WindowTrace.shades(colors)
        #expect(shades.map(\.location) == WindowTrace.stopLocations)
        #expect(shades[3] == WindowTrace.Shade(rgb: WindowTrace.websitePink, alpha: 1, location: 0.93))
        // The tip: the head's pink lightened a little, not white.
        let tip = WindowTrace.websitePink.mixed(with: .white, amount: 0.35)
        #expect(shades[4].rgb == tip)
        #expect(shades[4].rgb != shades[3].rgb)
        #expect(!shades.contains { $0.rgb == .white })
        #expect(shades.map(\.alpha) == [0, 0, 0.7, 1, 1, 0, 0])
    }

    @Test func runningCounterclockwiseTheGradientIsMirrored() {
        let colors = TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan)
        let shades = WindowTrace.shades(colors, clockwise: false)
        let locations = shades.map(\.location)
        #expect(locations == locations.sorted())
        #expect(zip(locations, [0, 0.04, 0.05, 0.07, 0.2, 0.36, 1]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(shades[2].rgb == WindowTrace.tip(colors))
        #expect(shades[3].rgb == WindowTrace.websitePink)
    }

    @Test func aShorterTailMovesItsStopsTowardTheHead() {
        let colors = TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan)
        let none = WindowTrace.shades(colors, tail: 0).map(\.location)
        #expect(none == [0, 0.93, 0.93, 0.93, 0.95, 0.96, 1])
        let half = WindowTrace.shades(colors, tail: 0.5).map(\.location)
        #expect(zip(half, [0, 0.785, 0.865, 0.93, 0.95, 0.96, 1]).allSatisfy { abs($0 - $1) < 1e-9 })
        let mirrored = WindowTrace.shades(colors, clockwise: false, tail: 0).map(\.location)
        #expect(zip(mirrored, [0, 0.04, 0.05, 0.07, 0.07, 0.07, 1]).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    private func frame(_ elapsed: Double, subagents: Bool = true, journey: TraceOverlay.Journey) -> WindowTrace.Frame {
        let lit = lighting(.racing(since: since, subagents: subagents))!
        return WindowTrace.frame(journey, lighting: lit, route: .all, in: rect, elapsed: elapsed)
    }

    @Test func alongTheBottomTheTailShrinksIntoEachCornerWhereTheHeadTurnsBack() {
        // A leg takes 0.6s: right to left, then back.
        let journey = TraceOverlay.Journey()
        #expect(frame(0.1, journey: journey).tail == 1)
        #expect(frame(0.3, journey: journey).tail == 1)
        #expect(frame(0.59, journey: journey).tail < 0.2)
        #expect(frame(0.61, journey: journey).tail < 0.2)
        #expect(frame(0.9, journey: journey).tail == 1)
        // Round a route's corners the tail keeps its length.
        let route = TraceOverlay.Journey()
        for elapsed in [0.59, 0.61, 1.19] { #expect(frame(elapsed, subagents: false, journey: route).tail == 1) }
    }

    @Test func alongTheBottomTheLightShowsOnlyThere() {
        let journey = TraceOverlay.Journey()
        // Fading the sides out as the head reaches the bottom edge.
        #expect(abs(frame(0.2, journey: journey).sides - 0.5) < 1e-9)
        #expect(frame(0.5, journey: journey).sides == 0)
        #expect(frame(5, journey: journey).sides == 0)
        let route = TraceOverlay.Journey()
        for elapsed in [0.2, 1.5, 2.1] { #expect(frame(elapsed, subagents: false, journey: route).sides == 1) }
    }

    @Test func theBottomGlowIsSofterThanUnderASkinTrace() {
        let journey = TraceOverlay.Journey()
        let bottom = frame(3, journey: journey).bottom
        #expect(abs(bottom - 0.5 * TraceFrame.intensity(elapsed: 3)) < 1e-9)
    }

    @Test func theFramesAheadAreTheFramesAsTheyCome() {
        let rect = CGRect(x: 1.5, y: 1.5, width: 400, height: 200)
        let step = 1.0 / 30
        for subagents in [false, true] {
            let lit = lighting(.racing(since: since, subagents: subagents))!
            let journey = TraceOverlay.Journey()
            // Under way, as when the next frames are handed on.
            _ = WindowTrace.frame(journey, lighting: lit, route: .all, in: rect, elapsed: 3.3)
            let before = journey.motion
            let ahead = WindowTrace.frames(journey, lighting: lit, route: .all, in: rect, from: 3.3, duration: 10, step: step)
            #expect(journey.motion == before)
            #expect(ahead.count == 301)
            #expect(ahead.contains { $0.bottom > 0 } == subagents)
            #expect(ahead.contains { $0.clockwise } && (!subagents || ahead.contains { !$0.clockwise }))
            for (i, frame) in ahead.enumerated() {
                let now = WindowTrace.frame(journey, lighting: lit, route: .all, in: rect, elapsed: 3.3 + Double(i) * step)
                #expect(frame == now)
            }
        }
    }

    @Test func theGradientStartsAtTheTopAndTurnsClockwise() {
        // Unit space in a flipped view: y runs down.
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
        #expect(near(WindowTrace.endPoint(turn: 0), CGPoint(x: 0.5, y: 0)))
        #expect(near(WindowTrace.endPoint(turn: 90), CGPoint(x: 1, y: 0.5)))
        #expect(near(WindowTrace.endPoint(turn: 180), CGPoint(x: 0.5, y: 1)))
        #expect(near(WindowTrace.endPoint(turn: 270), CGPoint(x: 0, y: 0.5)))
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
