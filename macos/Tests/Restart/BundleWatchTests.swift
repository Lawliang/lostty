#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct BundleWatchTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aReplacedExecutableIsAnUpdate() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let before = BundleWatch.stamp(atPath: exe.path)
        // As install-skins.sh does: remove, then copy in a new one.
        try FileManager.default.removeItem(at: exe)
        try Data("new".utf8).write(to: exe)
        #expect(BundleWatch.changed(before, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func theSameExecutableIsNot() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let stamp = BundleWatch.stamp(atPath: exe.path)
        #expect(!BundleWatch.changed(stamp, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func aMissingExecutableIsNotAnUpdate() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let stamp = BundleWatch.stamp(atPath: exe.path)
        try FileManager.default.removeItem(at: exe)
        #expect(!BundleWatch.changed(stamp, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func goingBackSwapsTheTwoBuilds() throws {
        let dir = try folder()
        let installed = dir.appendingPathComponent("Lostty.app")
        let previous = dir.appendingPathComponent("Lostty (previous).app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: installed.appendingPathComponent("which"))
        try Data("old".utf8).write(to: previous.appendingPathComponent("which"))
        try PreviousBuild.swap(installed: installed, previous: previous)
        #expect(try String(contentsOf: installed.appendingPathComponent("which"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: previous.appendingPathComponent("which"), encoding: .utf8) == "new")
    }

    @Test func goingBackOnlyWhenThePreviousIsOlder() throws {
        let dir = try folder()
        let installed = dir.appendingPathComponent("Lostty.app")
        let previous = dir.appendingPathComponent("Lostty (previous).app")
        for app in [installed, previous] {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: app.appendingPathComponent("Contents/MacOS/lostty"))
        }
        let older = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: previous.appendingPathComponent("Contents/MacOS/lostty").path)
        #expect(PreviousBuild.goesBack(previous: previous, installed: installed))
        #expect(!PreviousBuild.goesBack(previous: installed, installed: previous))
    }
}
#endif
