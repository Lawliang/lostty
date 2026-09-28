import Testing
@testable import Ghostty

struct SkinsTOMLTests {
    @Test func parsesTablesArraysAndScalars() throws {
        let sections = try SkinsTOML.parse("""
        # top comment
        [defaults]
        texture_opacity = 0.2   # trailing comment
        auto = false

        [skins.arca]
        background = "#12222b"
        logo = "~/a b/logo.svg"

        [[match]]
        path = "~/projectrepos/arca"
        skin = "arca"

        [[match]]
        path = "~/x#y"
        skin = "arca"
        """)
        #expect(sections.count == 5)
        #expect(sections[0] == TOMLSection(path: [], isArrayElement: false, values: [:], line: 0))
        #expect(sections[1] == TOMLSection(
            path: ["defaults"], isArrayElement: false,
            values: ["texture_opacity": .number(0.2), "auto": .bool(false)], line: 2))
        #expect(sections[2].path == ["skins", "arca"])
        #expect(sections[2].values["logo"] == .string("~/a b/logo.svg"))
        #expect(sections[3].isArrayElement)
        #expect(sections[4].values["path"] == .string("~/x#y"))
    }

    @Test func stringEscapes() throws {
        let sections = try SkinsTOML.parse(#"k = "a\"b\\c""#)
        #expect(sections[0].values["k"] == .string(#"a"b\c"#))
    }

    @Test(arguments: [
        "k = [1, 2]", "k = {a = 1}", "k = \"open", "k = 1979-05-27", "k = inf",
        "= 1", "bad key = 1", "[a", "[[a]", "k = \"x\" y", #"k = "\q""#,
    ])
    func rejectsUnsupported(_ input: String) {
        #expect(throws: TOMLError.self) { try SkinsTOML.parse(input) }
    }

    @Test func rejectsDuplicates() {
        #expect(throws: TOMLError.self) { try SkinsTOML.parse("[a]\nk = 1\nk = 2") }
        #expect(throws: TOMLError.self) { try SkinsTOML.parse("[a]\n[a]") }
    }

    @Test func errorsCarryLineNumbers() {
        #expect(throws: TOMLError(line: 3, message: "expected key = value")) {
            try SkinsTOML.parse("[a]\n\nnonsense")
        }
    }
}
