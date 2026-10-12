#if os(macOS)
import AppKit
import Combine
import LosttyRemote
import SwiftUI

/// Lostty's menu bar icon and menu.
@MainActor
final class LosttyStatusItem: NSObject, NSMenuDelegate {
    static let shared = LosttyStatusItem()
    static let enabledKey = "LosttyMenuBarIcon"

    static var isEnabled: Bool {
        get { UserDefaults.ghostty.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.ghostty.set(newValue, forKey: enabledKey)
            newValue ? shared.install() : shared.remove()
        }
    }

    private var item: NSStatusItem?
    private var watchers: Set<AnyCancellable> = []
    private let stayAwake = StayAwakeStore.shared

    func installIfEnabled() {
        if Self.isEnabled { install() }
    }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Lostty"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        updateIcon()
        stayAwake.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &watchers)
        ClaudeRuntime.shared.$awaiting.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &watchers)
    }

    func remove() {
        watchers.removeAll()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func updateIcon() {
        item?.button?.image = StatusIcon.image(on: stayAwake.isOn, dot: !ClaudeRuntime.shared.awaiting.isEmpty)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        stayAwake.refreshAvailability()
        if stayAwake.isOn { stayAwake.pollPower() }

        let toggle = NSMenuItem(title: "Stay Awake for Phone", action: stayAwake.isOn ? #selector(turnOff) : nil, keyEquivalent: "")
        toggle.target = self
        toggle.state = stayAwake.isOn ? .on : .off
        if !stayAwake.isOn {
            let durations = NSMenu()
            durations.autoenablesItems = false
            for duration in StayAwakeDuration.allCases {
                let d = NSMenuItem(title: duration.title, action: #selector(turnOn(_:)), keyEquivalent: "")
                d.target = self
                d.representedObject = duration.rawValue
                d.isEnabled = stayAwake.available
                durations.addItem(d)
            }
            toggle.submenu = durations
        }
        menu.addItem(toggle)
        if let status = StayAwakeMenuText.status(stayAwake.model.state, power: stayAwake.power,
                                                 permissionInstalled: stayAwake.permissionInstalled, now: Date()) {
            menu.addItem(disabled("   " + status))
        }
        if !stayAwake.available && !stayAwake.isOn {
            menu.addItem(action("Set Up Phone Access…", #selector(openPhoneAccess)))
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Phones"))
        let names = PhoneAccessNames(defaults: .ghostty).entries()
        let phones = PhoneAccessNames.phones(keysText: (try? AuthorizedKeysFile.standard.read()) ?? "", names: names)
        if phones.isEmpty { menu.addItem(disabled("   None paired")) }
        for phone in phones { menu.addItem(disabled("   " + phone.name)) }
        for session in AttachedPhones.current() { menu.addItem(disabled("   " + StayAwakeMenuText.attached(session))) }

        let rows = StayAwakeMenuText.claudeRows(
            phases: Set(ClaudeRuntime.shared.phases.keys), awaiting: ClaudeRuntime.shared.awaiting,
            title: { (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: $0)?.title })
        if !rows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Claude"))
            for row in rows {
                let r = NSMenuItem(title: "   \(row.waiting ? "●" : "○") \(row.title) — \(row.waiting ? "waiting for you" : "working")",
                                   action: #selector(focusPane(_:)), keyEquivalent: "")
                r.target = self
                r.representedObject = row.id
                menu.addItem(r)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("New Window", #selector(newWindow)))
        menu.addItem(action("Phone Access…", #selector(openPhoneAccess)))
        menu.addItem(action("Pair a Phone…", #selector(pairPhone)))
        let floors = NSMenu()
        for floor in StayAwakeStore.floors {
            let f = NSMenuItem(title: "\(floor)%", action: #selector(setFloor(_:)), keyEquivalent: "")
            f.target = self
            f.representedObject = floor
            f.state = floor == stayAwake.batteryFloor ? .on : .off
            floors.addItem(f)
        }
        let floorItem = NSMenuItem(title: "Battery Floor", action: nil, keyEquivalent: "")
        floorItem.submenu = floors
        menu.addItem(floorItem)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func turnOn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let duration = StayAwakeDuration(rawValue: raw) else { return }
        stayAwake.turnOn(duration)
        updateIcon()
    }

    @objc private func turnOff() {
        stayAwake.turnOff()
        updateIcon()
    }

    @objc private func setFloor(_ sender: NSMenuItem) {
        if let floor = sender.representedObject as? Int { stayAwake.batteryFloor = floor }
    }

    @objc private func openPhoneAccess() { PhoneAccessUI.show() }

    @objc private func pairPhone() {
        PhoneAccessUI.show()
        PhoneAccessUI.startPairingWhenReady()
    }

    @objc private func newWindow() {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.newWindow(nil)
    }

    @objc private func focusPane(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: id),
              let controller = surface.window?.windowController as? BaseTerminalController
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        surface.window?.makeKeyAndOrderFront(nil)
        controller.focusSurface(surface)
    }
}

/// The chibi axolotl as an 18 pt template image: outline when off, filled
/// (eyes cut out) when Stay Awake is on, a dot when a Claude is waiting.
enum StatusIcon {
    @MainActor
    static func image(on: Bool, dot: Bool) -> NSImage? {
        let line = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        let eyes = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        let view = ZStack(alignment: .topTrailing) {
            ZStack {
                if on {
                    AxolotlPart(kind: .gills(.left)).fill(.black)
                    AxolotlPart(kind: .gills(.right)).fill(.black)
                    AxolotlPart(kind: .tail).fill(.black)
                    AxolotlPart(kind: .body).fill(.black)
                    AxolotlPart(kind: .head).fill(.black)
                    AxolotlEyes().stroke(.black, style: eyes).blendMode(.destinationOut)
                } else {
                    AxolotlPart(kind: .gills(.left)).stroke(.black, style: line)
                    AxolotlPart(kind: .gills(.right)).stroke(.black, style: line)
                    AxolotlPart(kind: .tail).stroke(.black, style: line)
                    AxolotlPart(kind: .body).stroke(.black, style: line)
                    // The head covers the gills' and body's lines behind it.
                    AxolotlPart(kind: .head).fill(.black).blendMode(.destinationOut)
                    AxolotlPart(kind: .head).stroke(.black, style: line)
                    AxolotlEyes().stroke(.black, style: eyes)
                }
            }
            .compositingGroup()
            if dot { Circle().fill(.black).frame(width: 5, height: 5) }
        }
        .frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "Lostty"
        return image
    }
}
#endif
