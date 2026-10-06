#if os(macOS)
import Testing
@testable import Ghostty

struct TraceDrawTests {
    @Test func noiseIsDeterministicAndInRange() {
        for i in 0..<200 {
            let a = TraceDraw.noise(i, 7)
            #expect(a == TraceDraw.noise(i, 7))
            #expect(a >= 0 && a < 1)
        }
        #expect(TraceDraw.noise(1, 1) != TraceDraw.noise(2, 1))
        #expect(TraceDraw.noise(1, 1) != TraceDraw.noise(1, 2))
    }

    @Test func falloffIsBrightAtTheHeadAndDarkAtTheTailEnd() {
        #expect(TraceDraw.falloff(0) == 0)
        #expect(TraceDraw.falloff(1) == 1)
        var last = -1.0
        for i in 0...20 {
            let v = TraceDraw.falloff(Double(i) / 20)
            #expect(v >= last)
            last = v
        }
        // Most of the light sits near the head, like a motion streak.
        #expect(TraceDraw.falloff(0.5) < 0.3)
    }

    @Test func eachStyleHasItsOwnRenderer() {
        let types = BuiltinTrace.allCases.map { String(describing: type(of: TraceRenderers.renderer(for: $0))) }
        #expect(Set(types).count == BuiltinTrace.allCases.count)
    }

    @Test func everyStyleHasARenderer() {
        for style in BuiltinTrace.allCases {
            _ = TraceRenderers.renderer(for: style)
        }
    }
}
#endif
