#if os(macOS)
import LosttyRemote
import Testing
@testable import Lostty

struct SidebarMascotTests {
    @Test func theMascotStaysWhileItsBubbleIsOpen() {
        // A pane with no state (tmux doesn't know it, Claude stopped) still
        // shows the mascot while its bubble is open, so the bubble (and its
        // Esc monitor) never lose their anchor.
        #expect(SidebarMascot.isShown(state: nil, bubbleOpen: true))
        #expect(!SidebarMascot.isShown(state: nil, bubbleOpen: false))
        #expect(SidebarMascot.isShown(state: .idle, bubbleOpen: false))
    }
}
#endif
