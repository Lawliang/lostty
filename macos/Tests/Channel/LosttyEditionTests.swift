#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct LosttyEditionTests {
    @Test func aBuildWithoutAnEditionIsCore() {
        let others: [Any] = ["", "$(LOSTTY_EDITION)", "-orca", "or ca", "orca!", 1]
        for other in others {
            #expect(LosttyEdition(info: [LosttyEdition.infoKey: other]) == .core)
        }
        #expect(LosttyEdition(info: nil) == .core)
        #expect(LosttyEdition(info: [LosttyEdition.infoKey: "core"]).isCore)
    }

    @Test func anEditionKeepsItsBranchName() {
        #expect(LosttyEdition(info: [LosttyEdition.infoKey: "Orca"]).name == "orca")
        #expect(LosttyEdition(name: "agent-teams").title == "Agent Teams")
        #expect(!LosttyEdition(name: "orca").isCore)
    }

    @Test func onlyAnEditionNamesItselfAfterTheBeta() {
        #expect(LosttyChannel.beta.name(edition: .core) == "Lostty Beta")
        #expect(LosttyChannel.beta.name(edition: LosttyEdition(name: "orca")) == "Lostty Beta · Orca")
        #expect(LosttyChannel.stable.name(edition: LosttyEdition(name: "orca")) == "Lostty")
    }
}

struct EditionLibraryTests {
    private func entry(_ name: String, version: String? = "0.4", commit: String? = "abc1234") -> EditionLibrary.Entry {
        EditionLibrary.Entry(edition: LosttyEdition(name: name), url: URL(fileURLWithPath: "/tmp/\(name).app"),
                             version: version, commit: commit)
    }

    @Test func coreComesFirstThenByName() {
        let ordered = EditionLibrary.ordered([entry("zeta"), entry("core"), entry("orca")])
        #expect(ordered.map(\.edition.name) == ["core", "orca", "zeta"])
    }

    @Test func theMenuShowsOnlyWhenThereIsAnotherEdition() {
        #expect(!EditionLibrary.offersSwitch([], current: .core))
        #expect(!EditionLibrary.offersSwitch([entry("core")], current: .core))
        #expect(EditionLibrary.offersSwitch([entry("core"), entry("orca")], current: .core))
        #expect(EditionLibrary.offersSwitch([entry("core")], current: LosttyEdition(name: "orca")))
    }

    @Test func aLineNamesTheEditionAndItsBuild() {
        #expect(EditionLibrary.title(entry("orca", version: "0.4 beta 3")) == "Orca  0.4 beta 3 (abc1234)")
        #expect(EditionLibrary.title(entry("core", version: nil, commit: nil)) == "Core")
    }

    @Test func theLibraryListsOnlyCopiesFiledUnderTheirOwnEdition() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        func app(_ file: String, edition: String?) throws {
            let contents = folder.appendingPathComponent("\(file).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleShortVersionString": "0.4", "LosttyChannel": "beta"]
            info[LosttyEdition.infoKey] = edition
            #expect((info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
        }
        try app("core", edition: nil)
        try app("orca", edition: "orca")
        try app("misfiled", edition: "orca")
        #expect(EditionLibrary.entries(in: folder).map(\.edition.name) == ["core", "orca"])
    }

    @Test func installingKeepsTheReplacedBuildAsThePrevious() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        func app(_ name: String, marker: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try marker.write(to: url.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
            return url
        }
        let installed = try app("Lostty.app", marker: "core")
        let previous = try app("Lostty (previous).app", marker: "older")
        let orca = try app("orca.app", marker: "orca")
        let entry = EditionLibrary.Entry(edition: LosttyEdition(name: "orca"), url: orca, version: nil, commit: nil)
        try EditionLibrary.install(entry, installed: installed, previous: previous)
        func marker(_ url: URL) throws -> String {
            try String(contentsOf: url.appendingPathComponent("marker"), encoding: .utf8)
        }
        #expect(try marker(installed) == "orca")
        #expect(try marker(previous) == "core")
        #expect(try marker(orca) == "orca")
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("Lostty (installing).app").path))
    }
}
#endif
