#if os(macOS)
import AppKit
import LosttyRemote
import UserNotifications

/// Tells the phone something happened. Does nothing until "Lostty phone
/// push" adds APNs.
protocol PhoneNotifier {
    func notify(_ text: String)
}

struct NoPhoneNotifier: PhoneNotifier {
    func notify(_ text: String) {}
}

struct StayAwakeRecordStore {
    static let key = "LosttyStayAwakeRecord"
    var defaults: UserDefaults

    func load() -> StayAwakeRecord? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(StayAwakeRecord.self, from: $0) }
    }

    func save(_ record: StayAwakeRecord) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Self.key) }
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}

/// Runs `StayAwakeModel`: feeds it power readings every 5 s while on, and
/// performs its actions in order, stopping at the first failure.
@MainActor
final class StayAwakeStore: ObservableObject {
    static let shared = StayAwakeStore()

    static let floorKey = "LosttyStayAwakeFloor"
    static let durationKey = "LosttyStayAwakeDuration"
    static let floors = [10, 15, 20, 30]

    @Published private(set) var model = StayAwakeModel()
    @Published private(set) var available = false
    @Published private(set) var permissionInstalled = false

    private let control: PowerControl
    private let defaults: UserDefaults
    private let phone: PhoneNotifier
    private let readPower: () -> PowerState
    private let hasPairedPhone: () -> Bool
    private let notifyMac: (String) -> Void
    private let now: () -> Date
    private let requestNotifications: () -> Void
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init(
        control: PowerControl = SystemPowerControl(),
        defaults: UserDefaults = .ghostty,
        phone: PhoneNotifier = NoPhoneNotifier(),
        readPower: @escaping () -> PowerState = PowerReader.read,
        hasPairedPhone: @escaping () -> Bool = StayAwakeStore.anyPhonePaired,
        notifyMac: @escaping (String) -> Void = StayAwakeStore.postMacNotification,
        now: @escaping () -> Date = Date.init,
        requestNotifications: @escaping () -> Void = StayAwakeStore.requestNotificationAuthorization
    ) {
        self.control = control
        self.defaults = defaults
        self.phone = phone
        self.readPower = readPower
        self.hasPairedPhone = hasPairedPhone
        self.notifyMac = notifyMac
        self.now = now
        self.requestNotifications = requestNotifications
        model.batteryFloor = batteryFloor
    }

    var isOn: Bool { model.isOn }
    var until: Date? { if case .on(let until, _) = model.state { until } else { nil } }
    var power: PowerState? { model.power }

    var batteryFloor: Int {
        get { (defaults.object(forKey: Self.floorKey) as? Int) ?? 15 }
        set {
            defaults.set(newValue, forKey: Self.floorKey)
            model.batteryFloor = newValue
        }
    }

    var lastDuration: StayAwakeDuration {
        get { defaults.string(forKey: Self.durationKey).flatMap(StayAwakeDuration.init(rawValue:)) ?? .untilOff }
        set { defaults.set(newValue.rawValue, forKey: Self.durationKey) }
    }

    /// At launch: put back whatever a crashed Lostty left changed. Not
    /// after a restart that kept it on (`resume`).
    func start() {
        guard !isOn else { return }
        send(.launch(StayAwakeRecordStore(defaults: defaults).load()))
    }

    /// Restart to Update: it was on in the Lostty before. Keeps it on as it
    /// was, without touching the power settings: turning sleep back on,
    /// even briefly, could put a closed-lid Mac to sleep.
    func resume(until: Date?) {
        send(.resume(StayAwakeRecordStore(defaults: defaults).load(), until: until))
        if isOn { startPolling() }
    }

    func refreshAvailability() {
        permissionInstalled = control.hasPermission()
        available = permissionInstalled && hasPairedPhone()
    }

    func turnOn(_ duration: StayAwakeDuration) {
        refreshAvailability()
        guard available, !isOn else { return }
        requestNotifications()
        lastDuration = duration
        // Nothing has changed yet, so an unreadable baseline just means no start.
        guard let current = try? control.read() else {
            notifyMac(StayAwakeCopy.unreadable)
            return
        }
        send(.power(readPower()))
        send(.turnOn(until: duration.seconds.map { now().addingTimeInterval($0) }, current: current))
        if isOn { startPolling() }
    }

    func turnOff() {
        send(.turnOff)
    }

    /// Synchronous: AppKit is about to exit.
    func quit() {
        send(.quit)
    }

    func pollPower() {
        send(.power(readPower()))
        send(.tick)
    }

    private func startPolling() {
        timer?.invalidate()
        // .common so alerts and open menus don't stall the cut-offs.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPower() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // With the lid closed every window is hidden; keep App Nap off the poll.
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Stay Awake for Phone")
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func send(_ event: StayAwakeModel.Event) {
        let actions = model.handle(event, now: now())
        perform(actions)
        if !isOn { stopPolling() }
    }

    private func perform(_ actions: [StayAwakeAction]) {
        let records = StayAwakeRecordStore(defaults: defaults)
        for action in actions {
            switch action {
            case .saveRecord(let record): records.save(record)
            case .clearRecord: records.clear()
            case .notifyMac(let text): notifyMac(text)
            case .notifyPhone(let text): phone.notify(text)
            case .run(let command):
                do {
                    try control.run(command)
                } catch {
                    let failure = error as? PowerControlError ?? .failed(error.localizedDescription)
                    perform(model.handle(.controlFailed(failure, command: command), now: now()))
                    return
                }
            }
        }
    }

    static func anyPhonePaired() -> Bool {
        !AuthorizedKeys.phones(in: (try? AuthorizedKeysFile.standard.read()) ?? "").isEmpty
    }

    /// Asked when the person turns Stay Awake on, so its notices can show.
    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func postMacNotification(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Lostty"
        content.body = text
        content.userInfo = ["lostty": "stay-awake"]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
#endif
