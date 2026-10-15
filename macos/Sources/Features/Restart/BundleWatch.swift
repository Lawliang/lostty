#if os(macOS)
import Foundation

/// Notices this Lostty's app was replaced on disk (install.sh, a new
/// Debug build): its executable is a different file than at launch. Then
/// Restart to Update shows.
@MainActor
final class BundleWatch: ObservableObject {
    static let shared = BundleWatch()

    struct Stamp: Equatable {
        var inode: UInt64
        var modified: Date
    }

    @Published private(set) var updateReady = false

    private let executablePath = Bundle.main.executablePath
    private lazy var atLaunch: Stamp? = executablePath.flatMap(Self.stamp(atPath:))
    private var timer: Timer?

    func start() {
        _ = atLaunch
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { BundleWatch.shared.check() }
        }
    }

    func check() {
        guard !updateReady, let executablePath else { return }
        if Self.changed(atLaunch, Self.stamp(atPath: executablePath)) { updateReady = true }
    }

    nonisolated static func stamp(atPath path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let modified = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        return Stamp(inode: UInt64(info.st_ino), modified: modified)
    }

    /// A different file is there now. Missing (mid-install) is not a change.
    nonisolated static func changed(_ old: Stamp?, _ new: Stamp?) -> Bool {
        guard let old, let new else { return false }
        return old != new
    }
}
#endif
