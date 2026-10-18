#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Lostty

struct WindowTraceTests {
    private let a = UUID(), b = UUID(), c = UUID()
    private let since = Date(timeIntervalSinceReferenceDate: 0)

    private func skin(_ accent: String, _ accent2: String? = nil) -> Skin {
        var skin = Skin(name: accent, background: RGB(hex: "#101820")!, foreground: nil,
                        accent: RGB(hex: accent)!, texture: .none, textureOpacity: 0.16)
        skin.accent2 = accent2.flatMap(RGB.init(hex:))
        return skin
    }

    private func lighting(
        focused: UUID? = nil, _ phases: [UUID: TracePhase], skins: [UUID: Skin] = [:], enabled: Bool = true
    ) -> WindowTrace.Lighting? {
        WindowTrace.lighting(panes: [a, b, c], focused: focused, phases: phases, skin: { skins[$0] }, enabled: enabled)
    }

    @Test func darkWhileNothingWorks() {
        #expect(lighting([:]) == nil)
    }

    @Test func anyWorkingPaneLightsTheWindow() {
        #expect(lighting([c: .racing(since: since)])?.pane == c)
    }

    @Test func onlySubagentsWorkingLeavesItDark() {
        #expect(lighting([b: .racing(since: since, subagents: true)]) == nil)
    }

    @Test func theFocusedWorkingPaneWins() {
        let phases: [UUID: TracePhase] = [a: .racing(since: since), c: .racing(since: since)]
        #expect(lighting(focused: c, phases)?.pane == c)
        // An idle focused pane: the first working one in the window's order.
        #expect(lighting(focused: b, phases)?.pane == a)
        // Focus in another window's pane.
        #expect(lighting(focused: UUID(), phases)?.pane == a)
    }

    @Test func aPaneWithNoSkinGetsTheWebsitesPinkAndCyan() {
        let lit = lighting([a: .racing(since: since)])
        #expect(lit?.primary == RGB(hex: "#ff3df2")!)
        #expect(lit?.secondary == RGB(hex: "#28e7ff")!)
    }

    @Test func aSkinnedPaneUsesItsTraceColors() {
        let lit = lighting([b: .racing(since: since)], skins: [b: skin("#46a2ff", "#ffd23d")])
        #expect(lit?.primary == RGB(hex: "#46a2ff")!)
        #expect(lit?.secondary == RGB(hex: "#ffd23d")!)
    }

    @Test func panesWithTracesOffDontLightIt() {
        var off = skin("#46a2ff")
        off.trace = SkinTrace(disabled: true)
        let phases: [UUID: TracePhase] = [a: .racing(since: since), b: .racing(since: since)]
        #expect(lighting(focused: a, phases, skins: [a: off])?.pane == b)
        #expect(lighting(phases, enabled: false) == nil)
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

struct ReadyOverlayTests {
    @Test func theFirstWaitingPaneInTheWindowSpeaks() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(ClaudeReadyOverlay.waiting(in: [a, b, c], awaiting: []) == nil)
        #expect(ClaudeReadyOverlay.waiting(in: [a, b, c], awaiting: [c, b]) == b)
        // A pane waiting in another window doesn't cover this one.
        #expect(ClaudeReadyOverlay.waiting(in: [a, b], awaiting: [UUID()]) == nil)
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

    @Test func menuOffersSkinTracesThenWindowLight() {
        #expect(TraceStyle.allCases.map(\.title) == ["Skin Traces", "Window Light"])
    }

    @Test func onlySubagentsWorkingIsSubagentsOnly() {
        #expect(TracePhase.racing(since: Date(), subagents: true).subagentsOnly)
        #expect(!TracePhase.racing(since: Date()).subagentsOnly)
        #expect(!TracePhase.off.subagentsOnly)
    }
}
#endif
