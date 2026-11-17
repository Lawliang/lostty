#if os(macOS)
import AppKit
import LosttyRemote

/// The bar's model menu: the models Claude Code's own picker lists, and
/// `/model <id>` typed into the pane's idle Claude to switch.
enum ClaudeModelSwitch {
    static let catalogFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/cache/model-catalog")

    /// How long the bar's menu keeps a reading of the catalog. SwiftUI
    /// builds the menu each time a bar draws, which is every few seconds
    /// on every card.
    static let keep: TimeInterval = 60
    @MainActor private static var kept: (models: [AgentModel], at: Date)?

    /// `models(in:)` of Claude's own catalog, read at most once a minute.
    @MainActor
    static func menuModels(now: Date = Date()) -> [AgentModel] {
        if let kept, now.timeIntervalSince(kept.at) < keep { return kept.models }
        let models = models()
        kept = (models, now)
        return models
    }

    /// The models in the newest `…-cc.json` catalog, in its order; Claude's
    /// aliases for each family's latest when there's none.
    static func models(in folder: URL = catalogFolder) -> [AgentModel] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.filter { $0.lastPathComponent.hasSuffix("-cc.json") }.max { modified($0) < modified($1) }
        let listed = newest.flatMap { try? Data(contentsOf: $0) }.map(models(fromCatalog:)) ?? []
        return listed.isEmpty ? TerminalAgent.claude.fallbackModels : listed
    }

    static func models(fromCatalog data: Data) -> [AgentModel] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let catalog = root?["catalog"] as? [String: Any]
        let config = catalog?["config"] as? [String: Any]
        let entries = config?["models"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String, AgentModel.isName(id), seen.insert(id).inserted else { return nil }
            let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return AgentModel(id: id, name: name)
        }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Types `/model <id>` into the pane's Claude; false, and nothing
    /// typed, unless Claude waits with an empty input box.
    @MainActor
    static func switchTo(_ model: AgentModel, in pane: UUID) -> Bool {
        guard AgentModel.isName(model.id), ClaudeRuntime.shared.phase(pane).isOff,
              let view = PaneTyping.surface(pane) else { return false }
        let pid = ProcessInfo.processInfo.processIdentifier
        let session = CanvasController.shared
            .flatMap { TmuxOwnership.showing(pane, ownedBy: pid, in: $0.tmuxSessions).first?.id }
        guard TicketDelivery.input(in: TicketDelivery.screen(of: view, session: session)) == .empty else { return false }
        return TicketDelivery.type("/model \(model.id)", into: view)
    }
}
#endif
