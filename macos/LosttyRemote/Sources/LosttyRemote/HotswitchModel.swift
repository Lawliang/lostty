import Foundation

/// Hotswitch: while Stay Awake is on, moves a closed MacBook from Wi-Fi
/// that's gone (or has no internet) to the owner's iPhone hotspot, and back
/// to known Wi-Fi once it's in range again. macOS won't join a hotspot with
/// the lid closed. The rules only; the Mac side reads Wi-Fi, probes the
/// internet, joins and scans, and feeds the results back in.
public struct HotswitchModel: Sendable {
    /// No network this long: switch.
    public static let goneAfter: TimeInterval = 20
    /// On Wi-Fi with every probe failing this long: switch.
    public static let noInternetAfter: TimeInterval = 60
    /// Least time between two moves to the hotspot.
    public static let cooldown: TimeInterval = 600
    /// Least time between two tries at joining.
    public static let retryEvery: TimeInterval = 120
    /// A network just joined must reach the internet within this.
    public static let internetWithin: TimeInterval = 60
    /// While on the hotspot, look for known Wi-Fi this often.
    public static let scanEvery: TimeInterval = 120
    /// Scans in a row that must find it strong before leaving the hotspot.
    public static let strongScans = 2
    public static let strongRSSI = -70
    /// A network that had no internet when we went back to it.
    public static let ignoreFor: TimeInterval = 900

    public enum Action: Equatable, Sendable {
        /// Join the hotspot, then report `joined`.
        case join
        /// Leave the hotspot; macOS rejoins known Wi-Fi by itself.
        case leave
        /// Look for known Wi-Fi, then report `scanned`.
        case scan
        case notifyPhone(String)
        /// A quiet note, no push.
        case note(String)
        case log(String)
    }

    public enum Phase: Equatable, Sendable {
        case watching
        case joining
        /// On the hotspot, waiting for its internet.
        case confirming(since: Date)
        case onHotspot(lastScan: Date, strongScans: Int)
        /// Left the hotspot for this network; waiting for its internet.
        case returning(to: String, since: Date)
    }

    /// For the menu's status line.
    public enum Status: Equatable, Sendable {
        case onHotspot(since: Date)
        case failed(at: Date)
    }

    /// A known network a scan found.
    public struct Sighting: Equatable, Sendable {
        public var name: String
        public var rssi: Int

        public init(name: String, rssi: Int) {
            self.name = name
            self.rssi = rssi
        }
    }

    public static let moved = "Moved to your iPhone hotspot"
    public static let couldNotMove = "Couldn't move to your iPhone hotspot"
    public static func back(on network: String) -> String { "Back on \(network)" }

    public var hotspot: String
    public private(set) var phase: Phase = .watching
    public private(set) var status: Status?
    /// Stay Awake on, and hotswitch set up.
    public private(set) var active = false
    private var goneSince: Date?
    private var failingSince: Date?
    private var lastSwitch: Date?
    private var lastAttempt: Date?
    /// The phone heard "Couldn't move" in this outage.
    private var toldFailure = false
    private var ignored: [String: Date] = [:]

    public init(hotspot: String) {
        self.hotspot = hotspot
    }

    public mutating func setActive(_ on: Bool) -> [Action] {
        guard on != active else { return [] }
        active = on
        goneSince = nil
        failingSince = nil
        toldFailure = false
        guard !on else { return [] }
        let wasOn = phase
        // A join under way still reports back, and is left then.
        if wasOn != .joining { phase = .watching }
        status = nil
        switch wasOn {
        case .confirming, .onHotspot: return [.leave, .log("Stay Awake is off: leaving \(hotspot)")]
        case .watching, .joining, .returning: return []
        }
    }

    /// After Restart to Update: the Lostty before had moved the Mac to the
    /// hotspot, and it's still there.
    public mutating func resumeOnHotspot(now: Date) {
        guard active, phase == .watching else { return }
        phase = .onHotspot(lastScan: now, strongScans: 0)
        lastSwitch = now
        status = .onHotspot(since: now)
    }

    /// The Mac is on the hotspot because of hotswitch.
    public var holdsHotspot: Bool {
        switch phase {
        case .confirming, .onHotspot: true
        case .watching, .joining, .returning: false
        }
    }

    /// Every few seconds: the Wi-Fi network now (nil: none), and the
    /// internet probe's answer when one finished since the last tick.
    public mutating func tick(now: Date, network: String?, internet: Bool?) -> [Action] {
        guard active else { return [] }
        ignored = ignored.filter { $0.value > now }
        switch phase {
        case .joining:
            return []
        case .confirming(let since):
            if network == hotspot, internet == true {
                phase = .onHotspot(lastScan: now, strongScans: 0)
                lastSwitch = now
                status = .onHotspot(since: now)
                outageOver()
                return [.notifyPhone(Self.moved), .log("On \(hotspot), internet works")]
            }
            if network != hotspot {
                return failed("dropped off \(hotspot) before its internet worked", now: now)
            }
            if now.timeIntervalSince(since) >= Self.internetWithin {
                // Still better than nothing: stay, and come back to Wi-Fi later.
                phase = .onHotspot(lastScan: now, strongScans: 0)
                lastSwitch = now
                status = .onHotspot(since: now)
                return [.notifyPhone(Self.moved), .log("On \(hotspot), but no internet through it yet")]
            }
            return []
        case .onHotspot(let lastScan, let strong):
            if network != hotspot {
                phase = .watching
                status = nil
                guard let network else { return [.log("Dropped off \(hotspot)")] }
                return [.note(Self.back(on: network)), .log("Off \(hotspot), now on \(network)")]
            }
            guard now.timeIntervalSince(lastScan) >= Self.scanEvery else { return [] }
            phase = .onHotspot(lastScan: now, strongScans: strong)
            return [.scan]
        case .returning(let target, let since):
            if network == target, internet == true {
                phase = .watching
                status = nil
                return [.note(Self.back(on: target)), .log("Back on \(target)")]
            }
            guard now.timeIntervalSince(since) >= Self.internetWithin else { return [] }
            ignored[target] = now.addingTimeInterval(Self.ignoreFor)
            phase = .joining
            lastAttempt = now
            return [.log("No internet on \(target); back to \(hotspot), ignoring \(target) for 15 minutes"), .join]
        case .watching:
            return watch(now: now, network: network, internet: internet)
        }
    }

    public mutating func joined(error: String?, now: Date) -> [Action] {
        guard phase == .joining else { return [] }
        if let error { return failed(error, now: now) }
        guard active else {
            phase = .watching
            return [.leave, .log("Joined \(hotspot) after Stay Awake turned off: leaving")]
        }
        phase = .confirming(since: now)
        return [.log("Joined \(hotspot)")]
    }

    /// Known networks a scan found, not counting the hotspot.
    public mutating func scanned(_ sightings: [Sighting], now: Date) -> [Action] {
        guard active, case .onHotspot(let lastScan, let strong) = phase else { return [] }
        let best = sightings
            .filter { $0.name != hotspot && $0.rssi >= Self.strongRSSI && (ignored[$0.name] ?? .distantPast) <= now }
            .max { $0.rssi < $1.rssi }
        guard let best else {
            phase = .onHotspot(lastScan: lastScan, strongScans: 0)
            return []
        }
        guard strong + 1 >= Self.strongScans else {
            phase = .onHotspot(lastScan: lastScan, strongScans: strong + 1)
            return []
        }
        phase = .returning(to: best.name, since: now)
        return [.log("\(best.name) is in range (\(best.rssi) dBm): leaving \(hotspot)"), .leave]
    }

    private mutating func watch(now: Date, network: String?, internet: Bool?) -> [Action] {
        guard let network else {
            failingSince = nil
            // Off Wi-Fi but online (Ethernet): nothing to fix.
            if internet == true {
                goneSince = nil
                outageOver()
                return []
            }
            let since = goneSince ?? now
            goneSince = since
            guard now.timeIntervalSince(since) >= Self.goneAfter else { return [] }
            return attempt("Wi-Fi is gone", now: now)
        }
        goneSince = nil
        if network == hotspot {
            // Joined by hand or by macOS: not ours to manage.
            failingSince = nil
            return []
        }
        switch internet {
        case true?:
            failingSince = nil
            outageOver()
            if case .failed = status { status = nil }
            return []
        case false?:
            if failingSince == nil { failingSince = now }
        case nil:
            break
        }
        guard let since = failingSince, now.timeIntervalSince(since) >= Self.noInternetAfter else { return [] }
        return attempt("no internet on \(network)", now: now)
    }

    private mutating func attempt(_ why: String, now: Date) -> [Action] {
        if let lastSwitch, now.timeIntervalSince(lastSwitch) < Self.cooldown { return [] }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.retryEvery { return [] }
        lastAttempt = now
        phase = .joining
        return [.log("\(why): joining \(hotspot)"), .join]
    }

    private mutating func failed(_ why: String, now: Date) -> [Action] {
        phase = .watching
        status = .failed(at: now)
        var actions: [Action] = [.log("Couldn't join \(hotspot): \(why)")]
        if !toldFailure {
            toldFailure = true
            actions.append(.notifyPhone(Self.couldNotMove))
        }
        return actions
    }

    private mutating func outageOver() {
        goneSince = nil
        failingSince = nil
        toldFailure = false
    }
}
