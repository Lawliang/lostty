#if os(macOS)
import AppKit
import Combine

/// How hard the Mac is pressed, from the two things macOS reports: memory
/// pressure (it has started compressing or swapping to keep up) and heat
/// (it is about to slow the processor). Lostty can't cool the Mac or add
/// memory, so under strain it frees what its own idle terminals hold.
enum MacStrain: Int, Comparable {
    case none
    /// Memory pressure "warning", or thermal state "serious".
    case high
    /// Memory pressure or thermal state "critical".
    case critical

    static func < (a: MacStrain, b: MacStrain) -> Bool { a.rawValue < b.rawValue }

    enum Memory { case normal, warning, critical }

    /// `lidShut`: the Mac is kept awake with its lid closed and no other
    /// display (`MacStrainWatch.lidShut`). A closed lid covers the keyboard
    /// deck, which is part of how the Mac sheds heat.
    init(memory: Memory, thermal: ProcessInfo.ThermalState, lidShut: Bool = false) {
        switch (memory, thermal) {
        case (.critical, _), (_, .critical): self = .critical
        case (.warning, _), (_, .serious): self = .high
        default: self = lidShut ? .high : .none
        }
    }

    /// Idle minutes before a Claude card sleeps (`PaneSleep`), given the
    /// owner's setting. Under strain an idle card sleeps after five
    /// minutes: an idle Claude holds a few hundred megabytes, and it comes
    /// back where it left off. Sleep turned off (0) stays off.
    func sleepMinutes(setting: Int) -> Int {
        setting > 0 && self >= .high ? min(setting, Self.strainedSleepMinutes) : setting
    }

    static let strainedSleepMinutes = 5
}

/// Follows the Mac's memory pressure and thermal state. Both arrive as
/// events, so this costs nothing while they don't change.
@MainActor
final class MacStrainWatch: ObservableObject {
    static let shared = MacStrainWatch()

    @Published private(set) var strain: MacStrain = .none
    /// Stay Awake holds the Mac awake with its lid closed and nothing but
    /// the built-in display: nobody can see a window, so none draws.
    @Published private(set) var lidShut = false

    private var memory: MacStrain.Memory = .normal
    private var source: DispatchSourceMemoryPressure?
    private var thermal: NSObjectProtocol?
    private var lid: AnyCancellable?
    private var screens: NSObjectProtocol?
    private var lidClosed = false

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                let event = source.data
                self.memory = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
                self.update()
            }
        }
        source.resume()
        self.source = source
        // The source only reports changes: read where the level stands now.
        memory = Self.memoryNow()
        thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Stay Awake reads the lid every few seconds while it is on; with
        // it off a closed lid puts the Mac to sleep.
        lid = StayAwakeStore.shared.$model
            .map { $0.isOn && $0.power?.lidClosed == true }
            .removeDuplicates()
            .sink { [weak self] closed in
                MainActor.assumeIsolated {
                    self?.lidClosed = closed
                    self?.updateLid()
                }
            }
        // A display plugged in or pulled while the lid stays closed.
        screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLid() }
        }
        update()
    }

    private func updateLid() {
        let shut = Self.lidShut(closed: lidClosed, displays: Self.displaysNow())
        if shut != lidShut { lidShut = shut }
        update()
    }

    /// Whether each display is the Mac's own.
    static func displaysNow() -> [Bool] {
        NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id.map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }
    }

    /// A closed lid hides every window unless another display is attached
    /// (`displays`: whether each is built in).
    nonisolated static func lidShut(closed: Bool, displays builtIn: [Bool]) -> Bool {
        closed && builtIn.allSatisfy { $0 }
    }

    /// The kernel's memory pressure level now (1 normal, 2 warning, 4
    /// critical), which the source reports only when it changes.
    static func memoryNow() -> MacStrain.Memory {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return level >= 4 ? .critical : level >= 2 ? .warning : .normal
    }

    private func update() {
        let next = MacStrain(memory: memory, thermal: ProcessInfo.processInfo.thermalState, lidShut: lidShut)
        if next != strain { strain = next }
    }
}
#endif
