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

    @Test func oneLapEveryThreePointTwoSeconds() {
        #expect(WindowTrace.angle(elapsed: 0) == 0)
        #expect(abs(WindowTrace.angle(elapsed: 0.8) - 90) < 1e-9)
        #expect(abs(WindowTrace.angle(elapsed: 3.2 + 1.6) - 180) < 1e-9)
        #expect(WindowTrace.angle(elapsed: -1) == 0)
    }

    @Test func gradientMatchesTheWebsite() {
        #expect(WindowTrace.stopLocations == [0, 0.64, 0.80, 0.93, 0.95, 0.96, 1])
        let stops = WindowTrace.stops(TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan))
        #expect(stops.map { Double($0.location) } == WindowTrace.stopLocations)
        #expect(stops[3].color == TraceColors.color(WindowTrace.websitePink))
        #expect(stops[4].color == .white)
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
