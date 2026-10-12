#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct TraceRouteTests {
    private func freshDefaults() -> UserDefaults {
        let name = "TraceRouteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func newLosttyTracesTheRightEdge() {
        #expect(TraceRoute.current(in: freshDefaults()) == .right)
    }

    @Test func savedRouteIsRemembered() {
        let defaults = freshDefaults()
        for route in TraceRoute.allCases {
            TraceRoute.save(route, in: defaults)
            #expect(TraceRoute.current(in: defaults) == route)
        }
    }

    @Test func unknownSavedValueFallsBackToRight() {
        let defaults = freshDefaults()
        defaults.set("diagonal", forKey: TraceRoute.defaultsKey)
        #expect(TraceRoute.current(in: defaults) == .right)
    }

    @Test func menuOffersEveryRouteAllAroundFirst() {
        #expect(TraceRoute.allCases.map(\.title) == ["All Around", "Right Only", "Top Only", "Bottom Only", "Left Only"])
    }
}
#endif
