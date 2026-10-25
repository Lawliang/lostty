#if os(macOS)
import Foundation

/// Which zone each terminal pane on the canvas is in, as last worked out
/// (zones spec §5, §9).
struct CanvasPaneZones: Equatable {
    /// A pane's zone changed; nil is no zone.
    struct Move: Equatable {
        let pane: UUID
        let from: UUID?
        let to: UUID?
    }

    /// Every pane, in a zone or not.
    var panes: Set<UUID> = []
    /// The zone of each pane in one.
    var zones: [UUID: UUID] = [:]

    /// The panes in both whose zone changed, in pane order. A pane new in
    /// `new`, or gone from it, didn't move.
    func moves(to new: CanvasPaneZones) -> [Move] {
        panes.intersection(new.panes).sorted { $0.uuidString < $1.uuidString }.compactMap { pane in
            zones[pane] == new.zones[pane] ? nil : Move(pane: pane, from: zones[pane], to: new.zones[pane])
        }
    }
}

extension CanvasModel {
    /// Where the panes of `cards` are: each card's zone is its panes'.
    func paneZones(_ cards: [(id: UUID, panes: [UUID])]) -> CanvasPaneZones {
        var result = CanvasPaneZones()
        for card in cards {
            let holder = self.card(card.id).flatMap { entry in zone(for: entry.frame) }
            for pane in card.panes {
                result.panes.insert(pane)
                result.zones[pane] = holder
            }
        }
        return result
    }

    /// Zone `id` as its agents are told it: "Textberry › Onboarding" for a
    /// domain, "Textberry" for a project.
    func zoneTitle(_ id: UUID) -> String? {
        guard let zone = zone(id) else { return nil }
        guard let project = zone.parent.flatMap({ self.zone($0) }) else { return zone.name }
        return "\(project.name) › \(zone.name)"
    }

    /// What a new Claude session in zone `id` starts with: the zone, the
    /// folder its terminals start in, and the briefs.
    func zoneStart(_ id: UUID) -> String? {
        guard let title = zoneTitle(id) else { return nil }
        let folder = startFolder(ofZone: id).map { " (\(($0 as NSString).abbreviatingWithTildeInPath))" } ?? ""
        return (["Lostty zone: \(title)\(folder)."] + briefLines(id)).joined(separator: "\n")
    }

    /// What a running session is told when its pane moves into zone `id`.
    func zoneMovedIn(_ id: UUID) -> String? {
        guard let title = zoneTitle(id) else { return nil }
        return (["You're now in zone \(title)."] + briefLines(id)).joined(separator: "\n")
    }

    /// What a running session is told when its pane leaves the zone
    /// titled `title` for no zone.
    static func zoneMovedOut(of title: String) -> String {
        "You've left zone \(title)."
    }

    /// "Name: brief" for zone `id`'s project, then for the domain, leaving
    /// out an empty brief.
    private func briefLines(_ id: UUID) -> [String] {
        guard let zone = zone(id) else { return [] }
        return [zone.parent.flatMap { self.zone($0) }, zone].compactMap { zone in
            guard let zone else { return nil }
            let brief = zone.brief.trimmingCharacters(in: .whitespacesAndNewlines)
            return brief.isEmpty ? nil : "\(zone.name): \(brief)"
        }
    }

    /// The project zone `id` is in: itself, or its domain's project.
    func projectZone(_ id: UUID) -> UUID? {
        zone(id).map { $0.parent ?? $0.id }
    }

    /// The zone file of a pane in zone `id`. Its members are the tmux
    /// sessions (`sessions`, by pane) of every pane in the same project as
    /// `panes` has them, domains included; a pane with none is left out.
    func zoneFile(_ id: UUID, panes: CanvasPaneZones, sessions: [UUID: String]) -> CanvasZoneFile? {
        guard let title = zoneTitle(id), let start = zoneStart(id), let project = projectZone(id) else { return nil }
        let members = Set(panes.zones.compactMap { pane, zone in
            projectZone(zone) == project ? sessions[pane] : nil
        })
        return CanvasZoneFile(start: start, zone: title, folder: startFolder(ofZone: id), members: members.sorted())
    }
}

/// `<PANE>.zone.json`: what the hooks know of a pane's zone (zones spec
/// §7). `+claude-state start` prints `start`; `+claude-state tool` and
/// `+peers` keep to `members`, tmux session names on Lostty's socket.
struct CanvasZoneFile: Equatable, Encodable {
    let start: String
    let zone: String
    let folder: String?
    var members: [String] = []

    private enum CodingKeys: String, CodingKey { case start, zone, folder, members }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(zone, forKey: .zone)
        try container.encode(folder, forKey: .folder)
        try container.encode(members, forKey: .members)
    }
}

/// Each pane's zone files, in the context handoff's queue folder
/// (`ContextHandoffStore.panes`): `<PANE>.zone.json`, read by the hooks
/// and kept current, and `<PANE>.zone.say`, a move's note, taken by the
/// next prompt or tool call.
struct CanvasZoneStore: Sendable {
    static let standard = CanvasZoneStore(panes: ContextHandoffStore.standard.panes)

    let panes: URL

    private func file(_ pane: UUID, _ ext: String) -> URL {
        panes.appendingPathComponent("\(pane.uuidString).\(ext)")
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: panes, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func writeZone(_ pane: UUID, _ zone: CanvasZoneFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(zone) else { return }
        write(data, to: file(pane, "zone.json"))
    }

    func removeZone(_ pane: UUID) { try? FileManager.default.removeItem(at: file(pane, "zone.json")) }

    func writeSay(_ pane: UUID, _ text: String) { write(Data(text.utf8), to: file(pane, "zone.say")) }

    func removeSay(_ pane: UUID) { try? FileManager.default.removeItem(at: file(pane, "zone.say")) }
}
#endif
