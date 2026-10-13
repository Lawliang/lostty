import Foundation
import Testing
@testable import LosttyRemote

struct WarmTerminalsTests {
    typealias Key = WarmTerminals<String>.Key
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func key(_ id: String, _ name: String = "s") -> Key { Key(id: id, name: name) }

    @Test func reopeningTakesTheWarmOne() {
        var warm = WarmTerminals<String>()
        #expect(warm.put(key("$1"), "one", now: t0).isEmpty)
        #expect(warm.take(key("$1")) == "one")
        // In use again: no longer warm.
        #expect(warm.take(key("$1")) == nil)
    }

    @Test func aReusedIDWithAnotherNameIsAnotherSession() {
        var warm = WarmTerminals<String>()
        _ = warm.put(key("$1", "lostty"), "old", now: t0)
        #expect(warm.take(key("$1", "notes")) == nil)
    }

    @Test func theOldestGoesWhenAFourthComes() {
        var warm = WarmTerminals<String>(capacity: 3)
        _ = warm.put(key("$1"), "one", now: t0)
        _ = warm.put(key("$2"), "two", now: t0)
        _ = warm.put(key("$3"), "three", now: t0)
        #expect(warm.put(key("$4"), "four", now: t0) == ["one"])
        #expect(warm.keys.map(\.id) == ["$2", "$3", "$4"])
    }

    @Test func puttingBackAgainMovesItToTheNewestAndReturnsTheOld() {
        var warm = WarmTerminals<String>(capacity: 2)
        _ = warm.put(key("$1"), "one", now: t0)
        _ = warm.put(key("$2"), "two", now: t0)
        #expect(warm.put(key("$1"), "one again", now: t0) == ["one"])
        #expect(warm.put(key("$3"), "three", now: t0) == ["two"])
    }

    @Test func eachStaysFiveMinutesFromWhenItWasPutBack() {
        var warm = WarmTerminals<String>()
        _ = warm.put(key("$1"), "one", now: t0)
        _ = warm.put(key("$2"), "two", now: t0.addingTimeInterval(120))
        #expect(warm.nextExpiry == t0.addingTimeInterval(300))
        #expect(warm.expired(now: t0.addingTimeInterval(299)).isEmpty)
        #expect(warm.expired(now: t0.addingTimeInterval(300)) == ["one"])
        #expect(warm.nextExpiry == t0.addingTimeInterval(420))
        #expect(warm.expired(now: t0.addingTimeInterval(420)) == ["two"])
        #expect(warm.nextExpiry == nil)
    }

    @Test func removingBySessionAndAll() {
        var warm = WarmTerminals<String>()
        _ = warm.put(key("$1"), "one", now: t0)
        _ = warm.put(key("$2"), "two", now: t0)
        #expect(warm.remove { $0.id == "$1" } == ["one"])
        #expect(warm.removeAll() == ["two"])
        #expect(warm.count == 0)
    }
}
