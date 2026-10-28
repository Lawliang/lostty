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

    /// In a project, outside its domains, with how to claim a feature.
    func zoneMovedIn(_ id: UUID) -> String? {
        guard let title = zoneTitle(id) else { return nil }
        let claim = zone(id)?.parent == nil ? [Self.claimBrief] : []
        return (["You're now in zone \(title)."] + briefLines(id) + claim).joined(separator: "\n")
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

    /// What an agent outside its project's domains is told, so the zone's
    /// other agents know what it works on.
    static let claimBrief = "When you start on a feature, run lostty +ticket working \"<feature, a few words>\" "
        + "so the zone's other agents know."

    /// What project `id`'s manager is told (board spec §7): a feature line
    /// for each domain, with its brief's first line and the tmux sessions
    /// (`sessions`, by pane) of its panes as `panes` has them.
    ///
    ///     You're the manager of Textberry. You don't write code.
    ///     …
    ///     Features:
    ///       Login: the landing and login pages, end to end (textberry-3f)
    func managerBrief(_ id: UUID, panes: CanvasPaneZones, sessions: [UUID: String]) -> String? {
        guard let project = zone(id), project.parent == nil else { return nil }
        let features = zones.filter { $0.parent == id }.map { domain in
            let brief = domain.brief.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
            let agents = Set(panes.zones.compactMap { pane, zone in
                zone == domain.id && pane != project.manager ? sessions[pane] : nil
            })
            return "  \(domain.name)" + (brief.map { $0.isEmpty ? "" : ": \($0)" } ?? "")
                + (agents.isEmpty ? "" : " (\(agents.sorted().joined(separator: ", ")))")
        }
        return ([
            "You're the manager of \(project.name). You don't write code.",
            "Turn the owner's requests into tickets, one per feature, with "
                + "lostty +ticket add \"<feature>\" \"<summary>\" \"<details>\".",
            "Move a queued ticket to another feature with lostty +ticket assign <key> \"<feature>\".",
            features.isEmpty ? "Features: none yet." : "Features:",
        ] + features + ["Check lostty +ticket list first, so you don't repeat a ticket."]).joined(separator: "\n")
    }

    /// What each project's manager is told of the tickets that became
    /// blocked between `old` and `new`, when it sits inside its project as
    /// `panes` has it: "TB-8 · Onboarding is blocked: <reason>".
    func blockedNotes(from old: [CanvasTicket], to new: [CanvasTicket], panes: CanvasPaneZones) -> [(manager: UUID, text: String)] {
        new.compactMap { ticket in
            guard ticket.state == .blocked, let key = ticket.key,
                  let before = old.first(where: { $0.key == key }), before.state != .blocked,
                  let id = ticket.zone, let feature = zone(id), let project = projectZone(id),
                  let manager = zone(project)?.manager, panes.zones[manager].flatMap(projectZone) == project else { return nil }
            let reason = (ticket.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (manager, "\(key) · \(feature.name) is blocked" + (reason.isEmpty ? "." : ": \(reason)"))
        }
    }

    /// The project zone `id` is in: itself, or its domain's project.
    func projectZone(_ id: UUID) -> UUID? {
        zone(id).map { $0.parent ?? $0.id }
    }

    /// The zone file of a pane in zone `id`. Its members are the tmux
    /// sessions (`sessions`, by pane) of every pane in the same project as
    /// `panes` has them, domains included; a pane with none is left out.
    /// Its features are the domain each member in one works on, else what
    /// it `claims`. Its board is the project's `tickets` (`boardText`). The
    /// project's manager, `pane`, starts with its brief too; any other pane
    /// outside the domains, with how to claim a feature.
    func zoneFile(
        _ id: UUID, pane: UUID, panes: CanvasPaneZones, sessions: [UUID: String], claims: [UUID: String] = [:],
        tickets: [CanvasTicket]
    ) -> CanvasZoneFile? {
        guard let title = zoneTitle(id), let start = zoneStart(id), let project = projectZone(id) else { return nil }
        let members = Set(panes.zones.compactMap { pane, zone in
            projectZone(zone) == project ? sessions[pane] : nil
        })
        let manager = zone(project)?.manager
        var features: [String: String] = [:]
        for (member, zone) in panes.zones where projectZone(zone) == project {
            guard let session = sessions[member] else { continue }
            if zone != project, let domain = self.zone(zone) {
                features[session] = domain.name
            } else if features[session] == nil, let claim = claims[member] {
                features[session] = claim
            }
        }
        let brief = manager == pane ? managerBrief(project, panes: panes, sessions: sessions)
            : id == project ? Self.claimBrief : nil
        return CanvasZoneFile(
            start: [start, brief].compactMap { $0 }.joined(separator: "\n"), zone: title,
            folder: startFolder(ofZone: id), members: members.sorted(), features: features,
            board: boardText(project, tickets: tickets))
    }
}

/// `<PANE>.zone.json`: what the hooks know of a pane's zone (zones spec
/// §7). `+claude-state start` prints `start`; `+claude-state tool` and
/// `+peers` keep to `members`, tmux session names on Lostty's socket;
/// the brief names each other agent's feature from `features`;
/// `+ticket list` prints `board`.
struct CanvasZoneFile: Equatable, Encodable {
    let start: String
    let zone: String
    let folder: String?
    var members: [String] = []
    var features: [String: String] = [:]
    var board: String?

    private enum CodingKeys: String, CodingKey { case start, zone, folder, members, features, board }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(zone, forKey: .zone)
        try container.encode(folder, forKey: .folder)
        try container.encode(members, forKey: .members)
        if !features.isEmpty { try container.encode(features, forKey: .features) }
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

    /// The pane is in no zone: its Allow Once and its claim go too.
    func removeZone(_ pane: UUID) {
        for ext in ["zone.json", "zone.allow", "zone.claim"] { try? FileManager.default.removeItem(at: file(pane, ext)) }
    }

    func writeClaim(_ pane: UUID, _ feature: String) { write(Data(feature.utf8), to: file(pane, "zone.claim")) }

    /// Each pane's claim, as `writeClaim` left them.
    func claims() -> [UUID: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: panes.path)) ?? []
        return names.reduce(into: [:]) { claims, name in
            guard name.hasSuffix(".zone.claim"), let pane = UUID(uuidString: String(name.prefix(36))),
                  let text = try? String(contentsOf: file(pane, "zone.claim"), encoding: .utf8) else { return }
            claims[pane] = text
        }
    }

    /// A move's note: it replaces any note not yet taken, which an
    /// earlier move made stale.
    func replaceSay(_ pane: UUID, _ text: String) { write(Data(text.utf8), to: file(pane, "zone.say")) }

    /// A note that goes after any note not yet taken, so a move's note
    /// isn't dropped; one already queued isn't queued again.
    func appendSay(_ pane: UUID, _ text: String) {
        let url = file(pane, "zone.say")
        let queued = try? String(contentsOf: url, encoding: .utf8)
        if queued?.components(separatedBy: "\n\n").contains(text) == true { return }
        write(Data(((queued.map { $0 + "\n\n" } ?? "") + text).utf8), to: url)
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
                  ["zone.json", "zone.say", "zone.allow", "zone.claim"].contains(name[name.index(after: dot)...]) else { continue }
            try? FileManager.default.removeItem(at: panes.appendingPathComponent(name))
        }
    }
}
#endif
