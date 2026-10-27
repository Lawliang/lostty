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

    /// Whether the owner hears of `move`, worked out on the model
    /// `before` it and this one after: its pane left its project, for
    /// another or for none, and the zone it left is still here.
    func leftProject(_ move: CanvasPaneZones.Move, before: CanvasModel) -> Bool {
        guard let from = move.from, zone(from) != nil else { return false }
        return before.projectZone(from) != move.to.flatMap(projectZone)
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

    func zoneMovedIn(_ id: UUID) -> String? {
        guard let title = zoneTitle(id) else { return nil }
        return (["You're now in zone \(title)."] + briefLines(id)).joined(separator: "\n")
    }

    static func zoneMovedOut(of title: String) -> String {
        "You've left zone \(title)."
    }

    /// A card's title as a notice names it: a running command's title is
    /// its whole command line, so a long one ends in an ellipsis.
    static func noticeTitle(_ title: String, limit: Int = 40) -> String {
        title.count <= limit ? title : title.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
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

    /// Who pane `pane` is to the board, by where `panes` has it: its
    /// project's manager while it sits inside the project, else the agent
    /// of the domain it's in. nil in a project outside its domains, or in
    /// no zone.
    func ticketRole(of pane: UUID, panes: CanvasPaneZones) -> TicketActor? {
        guard let id = panes.zones[pane], let zone = zone(id), let project = projectZone(id) else { return nil }
        if self.zone(project)?.manager == pane { return .manager(project: project) }
        return zone.parent == nil ? nil : .agent(domain: id)
    }

    /// Project `project`'s feature named `name`, case and spaces at its
    /// ends aside; the first of two with one name.
    func feature(named name: String, in project: UUID) -> UUID? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        return zones.first { zone in
            zone.parent == project && zone.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(wanted) == .orderedSame
        }?.id
    }

    /// What `lostty +ticket list` prints in project `id`: each feature's
    /// tickets as its section on the board lists them, then To assign:
    ///
    ///     Textberry tickets, started when their feature's Claude is free
    ///     Login
    ///       TB-7  working  Add a "Continue with Google" button
    ///       TB-5  review   Sign-in copy · Changed the hero text
    ///     Onboarding
    ///       none
    ///     To assign
    ///       TB-11 queued   Dark mode
    func boardText(_ id: UUID, tickets: [CanvasTicket]) -> String? {
        guard let project = zone(id), project.parent == nil else { return nil }
        let list = TicketList(
            tickets: tickets, zones: ticketZones(shownIn: id), sections: ticketSections(shownIn: id), selected: nil,
            folded: [])
        let width = list.tickets.filter(list.shows).compactMap { $0.key?.count }.max() ?? 0
        let lines = list.sections.flatMap { section -> [String] in
            let title = switch section {
            case .feature(let feature): zone(feature)?.name ?? ""
            case .toAssign: "To assign"
            }
            let rows = list.tickets(in: section).map { ticket in
                let note = (ticket.note ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
                let key = (ticket.key ?? "").padding(toLength: width, withPad: " ", startingAt: 0)
                let state = ticket.state.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
                return "  \(key)  \(state)  \(ticket.summary)" + (note.isEmpty ? "" : " · \(note)")
            }
            return [title] + (rows.isEmpty ? ["  none"] : rows)
        }
        let starts = project.autoStart == true
            ? "started when their feature's Claude is free" : "started by the owner's Start on the board"
        return (["\(project.name) tickets, \(starts)"] + lines).joined(separator: "\n")
    }

    /// The project zone `id` is in: itself, or its domain's project.
    func projectZone(_ id: UUID) -> UUID? {
        zone(id).map { $0.parent ?? $0.id }
    }

    /// The zone file of a pane in zone `id`. Its members are the tmux
    /// sessions (`sessions`, by pane) of every pane in the same project as
    /// `panes` has them, domains included; a pane with none is left out.
    /// Its board is the project's `tickets` (`boardText`).
    func zoneFile(
        _ id: UUID, panes: CanvasPaneZones, sessions: [UUID: String], tickets: [CanvasTicket]
    ) -> CanvasZoneFile? {
        guard let title = zoneTitle(id), let start = zoneStart(id), let project = projectZone(id) else { return nil }
        let members = Set(panes.zones.compactMap { pane, zone in
            projectZone(zone) == project ? sessions[pane] : nil
        })
        return CanvasZoneFile(
            start: start, zone: title, folder: startFolder(ofZone: id), members: members.sorted(),
            board: boardText(project, tickets: tickets))
    }
}

/// `<PANE>.zone.json`: what the hooks know of a pane's zone (zones spec
/// §7). `+claude-state start` prints `start`; `+claude-state tool` and
/// `+peers` keep to `members`, tmux session names on Lostty's socket;
/// `+ticket list` prints `board`.
struct CanvasZoneFile: Equatable, Encodable {
    let start: String
    let zone: String
    let folder: String?
    var members: [String] = []
    var board: String?

    private enum CodingKeys: String, CodingKey { case start, zone, folder, members, board }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(zone, forKey: .zone)
        try container.encode(folder, forKey: .folder)
        try container.encode(members, forKey: .members)
        try container.encodeIfPresent(board, forKey: .board)
    }
}

/// Each pane's zone files, in the context handoff's queue folder
/// (`ContextHandoffStore.panes`): `<PANE>.zone.json`, read by the hooks
/// and kept current, `<PANE>.zone.say`, a move's note, taken by the
/// next prompt or tool call, and `<PANE>.zone.allow`, the owner's Allow
/// Once, taken by the one SendMessage it names.
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

    /// The pane is in no zone: its Allow Once goes too.
    func removeZone(_ pane: UUID) {
        for ext in ["zone.json", "zone.allow"] { try? FileManager.default.removeItem(at: file(pane, ext)) }
    }

    /// A move's note: it replaces any note not yet taken, which an
    /// earlier move made stale.
    func replaceSay(_ pane: UUID, _ text: String) { write(Data(text.utf8), to: file(pane, "zone.say")) }

    /// Allow Once's note: it goes after any note not yet taken, so a
    /// move's note isn't dropped.
    func appendSay(_ pane: UUID, _ text: String) {
        let url = file(pane, "zone.say")
        let queued = (try? String(contentsOf: url, encoding: .utf8)).map { $0 + "\n\n" } ?? ""
        write(Data((queued + text).utf8), to: url)
    }

    func removeSay(_ pane: UUID) { try? FileManager.default.removeItem(at: file(pane, "zone.say")) }

    /// The latest Allow Once wins.
    func writeAllow(_ pane: UUID, target: String) { write(Data(target.utf8), to: file(pane, "zone.allow")) }

    /// The zone files of every pane but `live`'s go: a quit or a crash
    /// left them, and the hooks mustn't read a zone for a pane no longer
    /// in it. The folder's other files stay.
    func sweep(keeping live: Set<UUID>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: panes.path)) ?? []
        for name in names {
            guard let dot = name.firstIndex(of: "."), let pane = UUID(uuidString: String(name[..<dot])), !live.contains(pane),
                  ["zone.json", "zone.say", "zone.allow"].contains(name[name.index(after: dot)...]) else { continue }
            try? FileManager.default.removeItem(at: panes.appendingPathComponent(name))
        }
    }
}
#endif
