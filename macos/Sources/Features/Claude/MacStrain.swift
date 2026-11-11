#if os(macOS)
import Combine
import Foundation

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

    init(memory: Memory, thermal: ProcessInfo.ThermalState) {
        switch (memory, thermal) {
        case (.critical, _), (_, .critical): self = .critical
        case (.warning, _), (_, .serious): self = .high
        default: self = .none
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

    private var memory: MacStrain.Memory = .normal
    private var source: DispatchSourceMemoryPressure?
    private var thermal: NSObjectProtocol?

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
        thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    private func update() {
        let next = MacStrain(memory: memory, thermal: ProcessInfo.processInfo.thermalState)
        if next != strain { strain = next }
    }
}
#endif
