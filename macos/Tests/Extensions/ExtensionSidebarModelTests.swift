#if os(macOS)
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    @Test func startsShownWithNothingOpen() {
        let model = ExtensionSidebarModel()
        #expect(model.isShown)
        #expect(model.active == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        #expect(model.active == .codebaseVisualizer)
        model.select(.codebaseVisualizer)
        #expect(model.active == nil)
    }

    @Test func hidingTheSidebarClosesTheOpenExtension() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        model.toggleShown()
        #expect(!model.isShown)
        #expect(model.active == nil)
        model.toggleShown()
        #expect(model.isShown)
        #expect(model.active == nil)
    }

    @Test func theVisualizerIsTheFirstExtension() {
        #expect(LosttyExtension.allCases.first == .codebaseVisualizer)
        #expect(LosttyExtension.codebaseVisualizer.title == "Codebase visualizer")
    }
}
#endif
