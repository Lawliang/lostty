#if os(macOS)
import Testing
@testable import Lostty

struct TerminalFontConfigTests {
    @Test func readsTheFontLines() {
        let text = """
        # font-size = 99
        font-family = "Menlo"
        font-family = Monaco
        font-size = 15.5
        adjust-cell-height = 10%
        """
        let settings = TerminalFontConfig.read(text)
        #expect(settings == TerminalFontSettings(family: "Menlo", size: 15.5, cellHeight: "10%"))
    }

    @Test func aResetStartsTheFamilyListOver() {
        let text = "font-family = Menlo\nfont-family = \"\"\nfont-family = Monaco\n"
        #expect(TerminalFontConfig.read(text).family == "Monaco")
        #expect(TerminalFontConfig.read("font-family = Menlo\nfont-family = \"\"\n").family == nil)
    }

    @Test func appendsMissingKeysUnderAHeader() {
        let text = "keybind = f1=text:yes\\r\n"
        let settings = TerminalFontSettings(family: "IBM Plex Mono", size: 15, cellHeight: "20%")
        #expect(TerminalFontConfig.write(settings, into: text) == """
        keybind = f1=text:yes\\r

        # Terminal font (Lostty Settings)
        font-family = "IBM Plex Mono"
        font-size = 15
        adjust-cell-height = 20%

        """)
    }

    @Test func replacesInPlaceAndDropsDuplicates() {
        let text = """
        font-size = 12
        theme = dark
        font-family = Menlo
        font-family = Monaco
        """
        let settings = TerminalFontSettings(family: "PT Mono", size: 14.5, cellHeight: nil)
        #expect(TerminalFontConfig.write(settings, into: text) == """
        font-size = 14.5
        theme = dark
        font-family = "PT Mono"

        """)
    }

    @Test func nilRemovesTheKey() {
        let text = "font-family = Menlo\ntheme = dark\nadjust-cell-height = 10%\n"
        #expect(TerminalFontConfig.write(TerminalFontSettings(), into: text) == "theme = dark\n")
    }

    @Test func newKeysJoinAnExistingHeader() {
        let text = "# Terminal font (Lostty Settings)\nfont-size = 15\n\ntheme = dark\n"
        let settings = TerminalFontSettings(family: nil, size: 15, cellHeight: "10%")
        #expect(TerminalFontConfig.write(settings, into: text)
            == "# Terminal font (Lostty Settings)\nadjust-cell-height = 10%\nfont-size = 15\n\ntheme = dark\n")
    }

    @Test func writeThenReadRoundTrips() {
        let settings = TerminalFontSettings(family: "Menlo", size: 16, cellHeight: "30%")
        let text = TerminalFontConfig.write(settings, into: "")
        #expect(TerminalFontConfig.read(text) == settings)
        #expect(TerminalFontConfig.write(settings, into: text) == text)
    }

    @Test func leavesCommentsAndOtherKeysAlone() {
        let text = "# font-family = Old\nfont-family-bold = Menlo Bold\n"
        let settings = TerminalFontSettings(family: "Menlo", size: nil, cellHeight: nil)
        #expect(TerminalFontConfig.write(settings, into: text)
            == "# font-family = Old\nfont-family-bold = Menlo Bold\n\n# Terminal font (Lostty Settings)\nfont-family = \"Menlo\"\n")
    }
}
#endif
