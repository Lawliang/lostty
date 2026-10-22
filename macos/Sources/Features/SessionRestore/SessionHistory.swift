#if os(macOS)
import Foundation

/// Every `LastSession` Lostty saved, newest `limit` kept: the current one
/// follows what's open, so panes that close together while Lostty runs
/// (as six did on 2026-10-21) leave it with nothing to continue. This log
/// keeps the session from before, for File → Reopen from History. A change
/// in layout only (windows moved, focus) updates the newest snapshot; new
/// or closed panes, or a pane's new conversation, make a new one.
struct SessionHistory {
    static let limit = 200

    let folder: URL

    struct Entry {
        let url: URL
        let session: LastSession
    }

    static func folder(bundleID: String, in parent: URL) -> URL {
        parent.appendingPathComponent("session-history-\(bundleID)", isDirectory: true)
    }

    static var standard: SessionHistory {
        SessionHistory(folder: folder(
            bundleID: Bundle.main.bundleIdentifier ?? "com.lawliang.lostty",
            in: LastSession.standardURL.deletingLastPathComponent()))
    }

    /// Adds `session`, or overwrites the newest snapshot when it holds the
    /// same panes and conversations.
    func record(_ session: LastSession) throws {
        let newest = files().first
        if let newest, let saved = LastSession.load(from: newest), saved.samePanes(as: session) {
            try session.save(to: newest)
            return
        }
        let stamp = Int64((session.at.timeIntervalSince1970 * 1000).rounded())
        var url = folder.appendingPathComponent("\(stamp).json")
        // Two snapshots in one millisecond: the later one goes after.
        if let newest, Self.stamp(newest).map({ $0 >= stamp }) == true {
            url = folder.appendingPathComponent("\((Self.stamp(newest) ?? stamp) + 1).json")
        }
        try session.save(to: url)
        for old in files().dropFirst(Self.limit) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// The snapshots, newest first; at most `max`.
    func entries(max: Int = limit) -> [Entry] {
        files().prefix(max).compactMap { url in LastSession.load(from: url).map { Entry(url: url, session: $0) } }
    }

    /// The snapshot files, newest first.
    private func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in Self.stamp(url).map { (url, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// The milliseconds a snapshot's file is named by.
    private static func stamp(_ url: URL) -> Int64? {
        guard url.pathExtension == "json" else { return nil }
        return Int64(url.deletingPathExtension().lastPathComponent)
    }
}

extension LastSession {
    /// The same panes and conversations, wherever the windows are.
    func samePanes(as other: LastSession) -> Bool {
        Set(panes) == Set(other.panes) && conversations == other.conversations
    }

    /// This session without what's open now: the tabs and canvas cards
    /// holding a pane in `openPanes` (a second pane with a running pane's id
    /// would end that pane's session when it closed), and the conversations
    /// running in `openConversations`. Nil when nothing's left to reopen.
    func reopenable(openPanes: Set<String>, openConversations: Set<String>) -> LastSession? {
        guard let windows = windows.without(panes: openPanes) else { return nil }
        let kept = Set(windows.paneIDs)
        return LastSession(
            at: at, windows: windows, panes: panes.filter { kept.contains($0) },
            conversations: conversations.filter { kept.contains($0.key) && !openConversations.contains($0.value.id) })
    }
}

extension WindowSnapshot {
    /// Every pane's id, from the saved tabs and cards (without making the
    /// panes, which would start them).
    var paneIDs: [String] {
        groups.flatMap { group in
            group.tabs.flatMap(Self.paneIDs(in:)) + (group.canvas.map { Self.paneIDs(in: $0.state) } ?? [])
        }
    }

    /// Without the tabs and canvas cards holding a pane in `open`; the
    /// canvas shows, so its cards are seen coming back. Nil when no window
    /// is left.
    func without(panes open: Set<String>) -> WindowSnapshot? {
        let kept: [Group] = groups.compactMap { group in
            var group = group
            if let canvas = group.canvas {
                guard let state = Self.canvasState(canvas.state, without: open) else { return nil }
                group.canvas?.state = state
                return group
            }
            let showing = group.tabs.indices.contains(group.selected) ? group.tabs[group.selected] : nil
            group.tabs = group.tabs.filter { open.isDisjoint(with: Self.paneIDs(in: $0)) }
            guard !group.tabs.isEmpty else { return nil }
            group.selected = showing.flatMap { group.tabs.firstIndex(of: $0) } ?? 0
            return group
        }
        return kept.isEmpty ? nil : WindowSnapshot(groups: kept)
    }

    /// The pane ids in a saved tab's or canvas's JSON: each pane is saved as
    /// `{"view": {"uuid": …}}` in its split tree.
    static func paneIDs(in json: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: json) else { return [] }
        return paneIDs(in: object)
    }

    private static func paneIDs(in object: Any) -> [String] {
        if let array = object as? [Any] { return array.flatMap { paneIDs(in: $0) } }
        guard let dictionary = object as? [String: Any] else { return [] }
        if let view = dictionary["view"] as? [String: Any], let id = view["uuid"] as? String { return [id] }
        return dictionary.values.flatMap { paneIDs(in: $0) }
    }

    /// `CanvasRestorableState` JSON without the cards holding a pane in
    /// `open`, and shown; nil when no card is left.
    private static func canvasState(_ state: Data, without open: Set<String>) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: state)) as? [String: Any],
              var saved = root["saved"] as? [String: Any],
              let cards = saved["cards"] as? [Any] else { return nil }
        let kept = cards.filter { open.isDisjoint(with: paneIDs(in: $0)) }
        guard !kept.isEmpty else { return nil }
        saved["cards"] = kept
        saved["visible"] = true
        root["saved"] = saved
        return try? JSONSerialization.data(withJSONObject: root)
    }
}
#endif
