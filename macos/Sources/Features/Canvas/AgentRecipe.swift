#if os(macOS)
import Foundation
import LosttyRemote

/// A kind of agent the + menu's New Agent list opens: a terminal that
/// starts Claude (or Codex) with its own instructions, model and skills.
/// Lostty has three built in; a Markdown file in `~/.config/lostty/agents`
/// adds one, or replaces a built-in one of the same name:
///
///     ---
///     name: Reviewer
///     icon: eye
///     agent: claude
///     model: opus
///     skills: code-review, run
///     ---
///     You review the branch you start in. …
///
/// `seat: manager` makes it its project's manager when it opens in a
/// project zone, as the Coordinator is.
struct AgentRecipe: Equatable, Identifiable {
    var name: String
    /// An SF Symbol.
    var icon = "person"
    var agent = TerminalAgent.claude
    var model: String?
    var takesManagerSeat = false
    var skills: [String] = []
    var instructions: String

    var id: String { name.lowercased() }

    /// Where your own agents live.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lostty/agents")
    }

    /// The built-in agents, then yours in name order; one of yours with a
    /// built-in one's name takes its place.
    static func all(in folder: URL = folder) -> [AgentRecipe] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let mine = files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).flatMap {
                    parse($0, fallbackName: url.deletingPathExtension().lastPathComponent)
                }
            }
        return merged(builtIn, mine)
    }

    static func merged(_ base: [AgentRecipe], _ mine: [AgentRecipe]) -> [AgentRecipe] {
        var result = base
        for recipe in mine {
            if let index = result.firstIndex(where: { $0.id == recipe.id }) {
                result[index] = recipe
            } else {
                result.append(recipe)
            }
        }
        return result
    }

    static func named(_ name: String, in recipes: [AgentRecipe]) -> AgentRecipe? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return recipes.first { $0.id == wanted }
    }

    /// A recipe file: optional front matter between `---` lines, then
    /// the instructions. nil when there are none.
    static func parse(_ text: String, fallbackName: String) -> AgentRecipe? {
        var lines = text.components(separatedBy: .newlines)
        var fields: [String: String] = [:]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            lines.removeSubrange(0...end)
        }
        let instructions = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        guard !instructions.isEmpty, !name.isEmpty else { return nil }
        var recipe = AgentRecipe(name: name, instructions: instructions)
        if let icon = fields["icon"], !icon.isEmpty { recipe.icon = icon }
        if let agent = fields["agent"].flatMap({ TerminalAgent(rawValue: $0.lowercased()) }) { recipe.agent = agent }
        recipe.model = fields["model"].flatMap { AgentModel.isName($0) ? $0 : nil }
        recipe.takesManagerSeat = fields["seat"]?.lowercased() == "manager"
        recipe.skills = (fields["skills"] ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'/")) }
            .filter { !$0.isEmpty }
        return recipe
    }

    /// What it's told before anything else: its instructions, its skills,
    /// then what Lostty knows of where it is (`context`).
    func prompt(context: [String]) -> String {
        let skillLine = skills.isEmpty ? [] : ["Use these skills when they fit: " + skills.map { "/\($0)" }.joined(separator: ", ") + "."]
        return ([instructions] + skillLine + context).joined(separator: "\n\n")
    }

    /// The shell command that starts it, with its prompt in `file`, as
    /// `name` (Claude shows it), and `message` as its first one. Codex
    /// has no added prompt, so the file is its first message, and holds
    /// `message` too.
    func commandLine(file: String, name: String, message: String?) -> String {
        let quote = Ghostty.Shell.quote
        let message = message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        switch agent {
        case .claude:
            return (["claude", "--name", quote(name)] + (model.map { ["--model", $0] } ?? [])
                + ["--append-system-prompt-file", quote(file)] + (message.map { [quote($0)] } ?? []))
                .joined(separator: " ")
        case .codex:
            return (["codex"] + (model.map { ["-m", $0] } ?? []) + ["\"$(cat \(quote(file)))\""]).joined(separator: " ")
        }
    }

    /// What `commandLine`'s file holds.
    func fileText(context: [String], message: String?) -> String {
        guard agent == .codex, let message, !message.isEmpty else { return prompt(context: context) }
        return prompt(context: context) + "\n\n" + message
    }

    static let builtIn: [AgentRecipe] = [
        AgentRecipe(
            name: "Coordinator", icon: "person.3", model: "opus", takesManagerSeat: true,
            instructions: """
            You're this project's Coordinator. You run the work. You don't write code yourself.

            How a request goes:
            1. Read the owner's request, the code it touches, and your notes file. Say back in a few lines \
            what you think they asked for, and wait for them to confirm before you plan.
            2. Split the work into tickets, one per feature, with \
            lostty +ticket add "<feature>" "<summary>" "<details>". In the details, name the files it may \
            change, what it can assume about the other tickets, and how to prove it works (a build, a test, \
            a screenshot). Run lostty +ticket list first so you don't repeat a ticket. A feature is a zone \
            inside the project; if one you need isn't there, ask the owner to draw it.
            3. For each feature with a ticket and no worker, open one on its own branch: \
            lostty +agent open Worker --feature="<feature>" --branch=<short-branch-name>. Lostty types the \
            feature's next ticket into it when it's free. At most 3 agents you opened can be open at once; \
            ask the owner to close finished ones.
            4. Lostty types news into this terminal, starting with "Lostty:": a ticket ready for review, a \
            blocked ticket, or a report from an agent you opened. Don't poll. Wait for it.
            5. When a ticket is ready for review, open a Verifier on it: \
            lostty +agent open Verifier "Check <key> on branch <branch>: <what to check>". It reports back \
            pass, or what's wrong. If something's wrong, add a ticket to the same feature saying what to fix.
            6. When the work passes, tell the owner what's ready, on which branches, and the proof. Never \
            merge, install, push or ship. The owner decides.
            7. Write decisions and what you learned to your notes file as you go, so the next session \
            doesn't start from zero.

            If lostty +ticket list says this terminal isn't in a project zone, ask the owner to drag your \
            card into a project zone and pick you as its manager.
            """),
        AgentRecipe(
            name: "Worker", icon: "hammer",
            instructions: """
            You're a Worker. You do one ticket at a time and report back.
            - Lostty types your ticket in, starting with its key. Do what it asks, in the files it names.
            - Work on the branch and folder you started in. Commit as you go. Don't merge, push or install.
            - Prove it works the way the ticket says before you report.
            - When it's done: lostty +ticket review <key> "<one line on what changed, and the proof>". \
            If you can't go on: lostty +ticket blocked <key> "<why>".
            - Then wait. The feature's next ticket may come in.
            """),
        AgentRecipe(
            name: "Verifier", icon: "checkmark.seal", skills: ["run"],
            instructions: """
            You're a Verifier. You check someone else's work. You don't change it.
            - Your first message names a ticket, a branch, and what to check. Find the branch's folder with \
            git worktree list and work there.
            - Build it, run the tests that matter, and use the real app the way a person would. Take a \
            screenshot or a measurement as proof.
            - Don't edit code, commit, merge, push or install.
            - Report once, then stop: lostty +agent report "<key>: pass. <proof>" or \
            lostty +agent report "<key>: problems. <what's wrong and how to see it>".
            """),
    ]
}

/// A `lostty +agent` request from a pane, parsed from its LOSTTY_AGENT user
/// var: a JSON array of strings, `["open", agent, message, feature,
/// branch]` (an empty string for each left out) or `["report", text]`.
enum AgentRequest: Equatable {
    case open(agent: String, message: String?, feature: String?, branch: String?)
    case report(String)

    static let userVar = "LOSTTY_AGENT"

    init?(json: String) {
        guard let words = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return nil }
        let trimmed = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func given(_ index: Int) -> String? { trimmed[index].isEmpty ? nil : trimmed[index] }
        switch (trimmed.first, trimmed.count) {
        case ("report", 2):
            guard let text = given(1) else { return nil }
            self = .report(text)
        case ("open", 5):
            guard let agent = given(1) else { return nil }
            if let branch = given(4), !BranchName.isValid(branch) { return nil }
            self = .open(agent: agent, message: given(2), feature: given(3), branch: given(4))
        default:
            return nil
        }
    }
}
#endif
