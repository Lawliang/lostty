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

    @Test func everyStyleHasARenderer() {
        for style in BuiltinTrace.allCases {
            _ = TraceRenderers.renderer(for: style)
        }
    }
}
#endif
