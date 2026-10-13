import AppKit

/// Lostty always shows its own icon, so this plugin no longer swaps icons.
///
/// Ghostty used it to apply alternate and custom icon styles. All it does now
/// is undo what older builds may have left behind: a custom icon stamped on the
/// app bundle or a custom Dock tile view, so the bundle's own icon shows.
class DockTilePlugin: NSObject, NSDockTilePlugIn {
    // WARNING: An instance of this class is alive as long as the app's icon is
    // in the Dock (running or not!), so keep state and processing to a minimum.

    private let pluginBundle = Bundle(for: DockTilePlugin.self)

    /// Determine the enclosing app bundle for the dock tile plugin bundle.
    ///
    /// We intentionally avoid matching a specific bundle name so renaming the
    /// app in Finder still works.
    static func appBundleURL(for pluginBundleURL: URL) -> URL? {
        var url = pluginBundleURL
        while true {
            if url.pathExtension.compare("app", options: .caseInsensitive) == .orderedSame {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                // Safety stop: this should only happen at filesystem root.
                return nil
            }

            url = parent
        }
    }

    /// The primary NSDockTilePlugin function.
    func setDockTile(_ dockTile: NSDockTile?) {
        guard let dockTile else { return }

        if let appBundlePath = Self.appBundleURL(for: pluginBundle.bundleURL)?.path {
            // Passing nil removes any custom icon an older build set on the bundle.
            NSWorkspace.shared.setIcon(nil, forFile: appBundlePath)
            NSWorkspace.shared.noteFileSystemChanged(appBundlePath)
        }

        DispatchQueue.main.async {
            dockTile.contentView = nil
            dockTile.display()
        }
    }
}

// This is required because of the DispatchQueue call above. This doesn't
// feel right but I don't know a better way to solve this.
extension NSDockTile: @unchecked @retroactive Sendable {}
