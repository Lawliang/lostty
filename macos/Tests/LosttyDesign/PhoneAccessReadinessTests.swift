#if os(macOS)
import Testing
@testable import Lostty

struct PhoneAccessReadinessTests {
    func row(_ state: PhoneAccessRow.State) -> PhoneAccessRow {
        PhoneAccessRow(id: .tmux, title: "", detail: "", state: state, fixes: [])
    }

    @Test func countsOnlyReadyRows() {
        #expect(PhoneAccessRow.readiness([row(.ok), row(.ok), row(.warning), row(.missing)]) == (2, 4))
        #expect(PhoneAccessRow.readiness([]) == (0, 0))
    }
}
#endif
