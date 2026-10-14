#if os(macOS)
import Combine
import CoreLocation
import Foundation
import LosttyRemote
import os

/// Runs `HotswitchModel` while Stay Awake is on: every 5 s reads the Wi-Fi
/// network, probes the internet every 15 s (every 5 s while waiting on a
/// network just joined), and joins, leaves and scans as the model says.
@MainActor
final class Hotswitch: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Hotswitch()

    static let enabledKey = "LosttyHotswitchEnabled"
    static let hotspotKey = "LosttyHotswitchHotspot"
    /// Turned on by itself once, when setup was first complete.
    static let autoEnabledKey = "LosttyHotswitchAutoEnabled"
    /// The Mac is on the hotspot because of hotswitch; survives Restart to Update.
    static let heldKey = "LosttyHotswitchHeld"

    private static let logger = Logger(subsystem: "com.lawliang.lostty", category: "hotswitch")

    @Published private(set) var status: HotswitchModel.Status?
    @Published private(set) var location: CLAuthorizationStatus = .notDetermined
    @Published private(set) var hasPassword = false
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            update()
        }
    }
    @Published var hotspot: String {
        didSet {
            defaults.set(hotspot, forKey: Self.hotspotKey)
            model.hotspot = hotspot
            refreshSetup()
        }
    }

    var phone: PhoneNotifier = NoPhoneNotifier()

    private let defaults: UserDefaults = .ghostty
    private let wifi = HotswitchWiFi()
    private let locationManager = CLLocationManager()
    private let session = URLSession(configuration: .ephemeral)
    private var model: HotswitchModel
    private var stayAwake: AnyCancellable?
    private var timer: Timer?
    private var ticks = 0
    private var probing = false
    private var probed: Bool?
    private var lastNetwork: String?

    override init() {
        let hotspot = UserDefaults.ghostty.string(forKey: Self.hotspotKey) ?? ""
        self.hotspot = hotspot
        self.enabled = UserDefaults.ghostty.bool(forKey: Self.enabledKey)
        model = HotswitchModel(hotspot: hotspot)
        super.init()
        locationManager.delegate = self
        location = locationManager.authorizationStatus
    }

    var locationAllowed: Bool { location == .authorizedAlways }
    var ready: Bool { !hotspot.isEmpty && hasPassword && locationAllowed }

    func start() {
        guard stayAwake == nil else { return }
        refreshSetup()
        stayAwake = StayAwakeStore.shared.$model.sink { [weak self] _ in
            // $model publishes before the change lands.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.update() } }
        }
    }

    /// Synchronous: AppKit is about to exit, after Stay Awake turned off.
    func quit() {
        timer?.invalidate()
        timer = nil
        perform(model.setActive(false))
    }

    /// Known Wi-Fi networks for the picker; the current one first.
    func knownNetworks() -> [String] {
        var names = wifi.knownNetworks()
        if let current = wifi.network(), let index = names.firstIndex(of: current) {
            names.insert(names.remove(at: index), at: 0)
        }
        return names
    }

    func askForLocation() {
        locationManager.requestAlwaysAuthorization()
    }

    func savePassword(_ password: String) {
        guard !hotspot.isEmpty, !password.isEmpty else { return }
        HotspotPassword.save(password, for: hotspot)
        refreshSetup()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.location = status
            self.refreshSetup()
        }
    }

    private func refreshSetup() {
        hasPassword = !hotspot.isEmpty && HotspotPassword.exists(hotspot)
        if ready, !defaults.bool(forKey: Self.autoEnabledKey) {
            defaults.set(true, forKey: Self.autoEnabledKey)
            enabled = true
        }
        update()
    }

    private func update() {
        let want = enabled && ready && StayAwakeStore.shared.isOn
        guard want != model.active else { return }
        perform(model.setActive(want))
        if want {
            if defaults.bool(forKey: Self.heldKey), wifi.network() == hotspot {
                model.resumeOnHotspot(now: Date())
                publish()
            }
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTimer() {
        timer?.invalidate()
        ticks = 0
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let network = wifi.network()
        if network != lastNetwork {
            lastNetwork = network
            probed = nil
        }
        let internet = probed
        probed = nil
        perform(model.tick(now: Date(), network: network, internet: internet))
        ticks += 1
        let waiting: Bool
        switch model.phase {
        case .confirming, .returning: waiting = true
        case .watching, .joining, .onHotspot: waiting = false
        }
        guard !probing, waiting || ticks % 3 == 1 else { return }
        probing = true
        Task {
            let ok = await HotswitchWiFi.probe(session)
            probing = false
            // A probe that straddled a network change says nothing about the new one.
            if wifi.network() == network { probed = ok }
        }
    }

    private func perform(_ actions: [HotswitchModel.Action]) {
        for action in actions {
            switch action {
            case .join:
                let wifi = wifi, name = hotspot, password = HotspotPassword.read(hotspot) ?? ""
                Task.detached(priority: .userInitiated) {
                    let error = wifi.join(name, password: password)
                    await MainActor.run { Hotswitch.shared.joined(error) }
                }
            case .leave:
                wifi.leave()
            case .scan:
                let wifi = wifi, name = hotspot
                Task.detached(priority: .utility) {
                    let sightings = wifi.sightings(excluding: name)
                    await MainActor.run { Hotswitch.shared.scanned(sightings) }
                }
            case .notifyPhone(let text):
                Self.logger.notice("phone: \(text, privacy: .public)")
                phone.notify(text)
            case .note(let text):
                Self.logger.notice("note: \(text, privacy: .public)")
            case .log(let text):
                Self.logger.notice("\(text, privacy: .public)")
            }
        }
        publish()
    }

    private func joined(_ error: String?) {
        probed = nil
        perform(model.joined(error: error, now: Date()))
    }

    private func scanned(_ sightings: [HotswitchModel.Sighting]) {
        perform(model.scanned(sightings, now: Date()))
    }

    private func publish() {
        if status != model.status { status = model.status }
        defaults.set(model.holdsHotspot, forKey: Self.heldKey)
    }
}
#endif
