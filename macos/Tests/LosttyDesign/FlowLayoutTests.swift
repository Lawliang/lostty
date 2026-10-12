import CoreGraphics
import Testing
@testable import Ghostty

struct FlowLayoutTests {
    let button = CGSize(width: 100, height: 28)

    @Test func fitsOnOneLine() {
        #expect(FlowLayout.origins(for: [button, CGSize(width: 50, height: 28)], maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0)])
    }

    @Test func wrapsWhenTheNextDoesNotFit() {
        // "Turn Off Password Logins…" then "Skip" in a narrow column.
        #expect(FlowLayout.origins(for: [CGSize(width: 200, height: 28), CGSize(width: 120, height: 28)],
                                   maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 36)])
    }

    @Test func aWideChildStillStartsTheFirstLine() {
        #expect(FlowLayout.origins(for: [CGSize(width: 400, height: 28)], maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0)])
    }

    @Test func noChildrenNoOrigins() {
        #expect(FlowLayout.origins(for: [], maxWidth: 300, spacing: 8).isEmpty)
    }
}
