#if os(macOS)
import AppKit

/// Which part of a pane's edge the Claude trace travels while Claude works:
/// the whole border, or back and forth along one side. The bottom edge is
/// kept for subagents and background shells (TraceCourse.subagents).
/// Saved in user defaults and set from Lostty → Claude Trace Path.
enum TraceRoute: String, CaseIterable {
    case all, right, top, left

    static let defaultsKey = "LosttyTraceRoute"
    /// What a new Lostty shows until the person picks another.
    static let initial: TraceRoute = .right

    var title: String {
        switch self {
        case .all: "All Around"
        case .right: "Right Only"
        case .top: "Top Only"
        case .left: "Left Only"
        }
    }

    static func current(in defaults: UserDefaults = .ghostty) -> TraceRoute {
        defaults.string(forKey: defaultsKey).flatMap(TraceRoute.init(rawValue:)) ?? initial
    }

    static func save(_ route: TraceRoute, in defaults: UserDefaults = .ghostty) {
        defaults.set(route.rawValue, forKey: defaultsKey)
    }
}

/// The Lostty → Claude Trace Path submenu, one checkmarked item per route.
@MainActor
final class TraceRouteMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = TraceRouteMenu()

    static func install(after anchor: NSMenuItem) {
        guard let menu = anchor.menu else { return }
        let submenu = NSMenu(title: "Claude Trace Path")
        submenu.delegate = shared
        for route in TraceRoute.allCases {
            let item = NSMenuItem(title: route.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = shared
            item.representedObject = route.rawValue
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let note = NSMenuItem(title: "Bottom edge: only subagents or shells working", action: nil, keyEquivalent: "")
        note.isEnabled = false
        submenu.addItem(note)
        let item = NSMenuItem(title: "Claude Trace Path", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = TraceRoute.current()
        for item in menu.items where item.representedObject != nil {
            item.state = item.representedObject as? String == current.rawValue ? .on : .off
        }
    }

    /// The window light always goes all the way round: no path to pick.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        TraceStyle.current() != .window
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let route = TraceRoute(rawValue: raw) else { return }
        TraceRoute.save(route)
    }
}
#endif
