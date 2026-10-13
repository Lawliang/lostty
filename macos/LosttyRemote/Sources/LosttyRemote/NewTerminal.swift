import Foundation

/// Lostty Mobile: a terminal the phone asks the Mac to open, in a project
/// folder, optionally on a new branch in a worktree of its own, optionally
/// with an agent CLI (`TerminalAgent`) started. The Mac does it, so the shell is Lostty's (with
/// Claude's hooks) in a window of its own.
///
/// The phone writes the request to a global tmux option (`requestOption`)
/// and signals; the Mac's Lostty claims it (unsets it), opens the window,
/// and answers in `answerOption` (`NewTerminalAnswer`).
public struct NewTerminalRequest: Codable, Equatable, Sendable {
    public static let requestPrefix = "@lostty_new_"
    public static let answerPrefix = "@lostty_made_"

    /// Twelve lowercase hex digits: part of the option names.
    public var id: String
    /// The project's folder on the Mac.
    public var folder: String
    /// A new branch to make (in `<repo>/.claude/worktrees/<name>`), if any.
    public var branch: String?
    /// Started in the new terminal (its command typed), if any.
    public var agent: TerminalAgent?
    /// The agent's options chosen (`TerminalAgent.Option.id`); ones the
    /// agent doesn't have are ignored.
    public var agentOptions: [String]?
    /// The agent's model (`AgentModel.id`); nil: the agent's own default.
    public var model: String?

    public init(
        folder: String, branch: String? = nil, agent: TerminalAgent?, agentOptions: [String]? = nil,
        model: String? = nil, id: String = NewTerminalRequest.newID()
    ) {
        self.id = id
        self.folder = folder
        self.branch = branch
        self.agent = agent
        self.agentOptions = agentOptions
        self.model = model
    }

    /// What the new terminal types first, if anything.
    public var startCommand: String? {
        agent?.commandLine(Set(agentOptions ?? []), model: model)
    }

    public static func newID() -> String {
        String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(12))
    }

    public var requestOption: String { Self.requestPrefix + id }
    public var answerOption: String { Self.answerPrefix + id }

    public var encoded: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// nil unless it's a request with a sound id, an absolute folder and a
    /// branch git would take.
    public init?(encoded: String) {
        guard let request = try? JSONDecoder().decode(Self.self, from: Data(encoded.utf8)),
              Self.isID(request.id), request.folder.hasPrefix("/"),
              request.branch.map(BranchName.isValid) ?? true,
              request.model.map(AgentModel.isName) ?? true else { return nil }
        self = request
    }

    static func isID(_ s: String) -> Bool {
        s.count == 12 && s.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }

    /// The request's id in a request option's name; nil for other options.
    public static func id(ofRequestOption name: String) -> String? {
        guard name.hasPrefix(requestPrefix) else { return nil }
        let id = String(name.dropFirst(requestPrefix.count))
        return isID(id) ? id : nil
    }
}

/// An agent CLI a new terminal can start in.
public enum TerminalAgent: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    /// What's typed to start it.
    public var command: String { rawValue }

    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// A choice the agent starts with: its own fixed arguments.
    public struct Option: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        let arguments: [String]
    }

    /// In the order their arguments go on the command line.
    public var options: [Option] {
        switch self {
        case .claude: []
        case .codex: [
            // A subcommand: first.
            Option(id: "resume", name: "Resume Last Session", arguments: ["resume", "--last"]),
            Option(id: "skipApprovals", name: "Skip Approvals and Sandbox", arguments: ["--dangerously-bypass-approvals-and-sandbox"]),
            Option(id: "search", name: "Web Search", arguments: ["--search"]),
        ]
        }
    }

    /// When the Mac lists none (`TmuxRemote.agentModelsCommand`): Claude's
    /// aliases for each family's latest.
    public var fallbackModels: [AgentModel] {
        switch self {
        case .claude: [AgentModel(id: "fable", name: "Fable"), AgentModel(id: "opus", name: "Opus"), AgentModel(id: "sonnet", name: "Sonnet")]
        case .codex: []
        }
    }

    var modelFlag: String {
        switch self {
        case .claude: "--model"
        case .codex: "-m"
        }
    }

    /// The command with the options `chosen` (by id) that it has, then
    /// `model` (after the options: Codex's resume is a subcommand).
    public func commandLine(_ chosen: Set<String>, model: String? = nil) -> String {
        let model = model.flatMap { AgentModel.isName($0) ? [modelFlag, $0] : nil } ?? []
        return ([command] + options.filter { chosen.contains($0.id) }.flatMap(\.arguments) + model).joined(separator: " ")
    }
}

/// The models an agent can start with, and the one it starts with when
/// given none.
public struct AgentModelList: Equatable, Sendable {
    public var models: [AgentModel]
    public var defaultModel: AgentModel?

    public init(models: [AgentModel], defaultModel: AgentModel?) {
        self.models = models
        self.defaultModel = defaultModel
    }
}

/// A model an agent can start with.
public struct AgentModel: Hashable, Sendable, Identifiable {
    /// What the agent's model flag takes.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// Typed into a shell on the Mac: plain characters only.
    public static func isName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 && !name.hasPrefix("-")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-:".contains($0)) }
    }
}

/// The Mac's answer to a `NewTerminalRequest`.
public enum NewTerminalAnswer: Equatable, Sendable {
    /// The new terminal's session ("$12").
    case made(sessionID: String)
    /// Why it couldn't, for the phone to show.
    case failed(String)

    /// "$12", or "!" and why.
    public init?(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("!") {
            self = .failed(String(value.dropFirst()))
        } else if TmuxRemote.isSessionID(value) {
            self = .made(sessionID: value)
        } else {
            return nil
        }
    }

    public var encoded: String {
        switch self {
        case .made(let id): id
        case .failed(let why): "!" + why.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// Branch names git takes (`git check-ref-format --branch`, near enough;
/// git has the last word).
public enum BranchName {
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 200, !name.hasPrefix("-"), !name.hasPrefix("/"),
              !name.hasSuffix("/"), !name.hasSuffix("."), !name.hasSuffix(".lock"), name != "@",
              !name.contains(".."), !name.contains("//"), !name.contains("@{") else { return false }
        let banned = Set(" ~^:?*[\\")
        return !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
            && !name.contains(where: banned.contains)
            && !name.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// The worktree's folder: the branch with "/" as "-".
    public static func folderName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
    }
}

/// Folders found below one on the Mac (`searchFoldersCommand`).
public struct FolderSearch: Equatable, Sendable {
    public struct Hit: Equatable, Sendable, Identifiable {
        /// Absolute.
        public var path: String
        public var isRepo: Bool
        /// Folders down from the one searched: 1 is directly in it.
        public var depth: Int
        public var id: String { path }
        public var name: String { (path as NSString).lastPathComponent }

        public init(path: String, isRepo: Bool, depth: Int) {
            self.path = path
            self.isRepo = isRepo
            self.depth = depth
        }
    }

    /// The folder searched, absolute.
    public var path: String
    /// The shallowest first.
    public var hits: [Hit]

    public init(path: String, hits: [Hit]) {
        self.path = path
        self.hits = hits
    }
}

/// One folder on the Mac, as the phone browses for a new terminal's:
/// where it is, whether it's a git repo, and the folders in it.
public struct MacFolder: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var name: String
        public var isRepo: Bool
        public var id: String { name }

        public init(name: String, isRepo: Bool) {
            self.name = name
            self.isRepo = isRepo
        }
    }

    /// Absolute, as the Mac's shell has it.
    public var path: String
    public var isRepo: Bool
    /// By name; hidden ones left out.
    public var folders: [Entry]

    public init(path: String, isRepo: Bool, folders: [Entry]) {
        self.path = path
        self.isRepo = isRepo
        self.folders = folders
    }

    /// The folder in it named `name`.
    public func path(of name: String) -> String {
        path == "/" ? "/" + name : path + "/" + name
    }
}

extension TmuxRemote {
    /// Asks the Mac for a new terminal, then wakes it. Exits 1 when no
    /// tmux server runs (no Lostty to ask).
    public static func requestNewTerminalCommand(_ request: NewTerminalRequest) -> String {
        "\(tmux) -f /dev/null set-option -g \(shellQuote(request.requestOption)) \(shellQuote(request.encoded))"
            + " \\; wait-for -S \(changedChannel)"
    }

    /// The Mac's answer so far: empty while there is none.
    public static func newTerminalAnswerCommand(id: String) -> String {
        "\(tmux) -f /dev/null show-options -gqv \(shellQuote(NewTerminalRequest.answerPrefix + id))"
    }

    /// Takes back a request (one the Mac never claimed must not open a
    /// window later) and drops its answer.
    public static func clearNewTerminalCommand(id: String) -> String {
        "\(tmux) -f /dev/null set-option -gu \(shellQuote(NewTerminalRequest.requestPrefix + id))"
            + " \\; set-option -gu \(shellQuote(NewTerminalRequest.answerPrefix + id)) 2>/dev/null; true"
    }

    /// Lists folder `path` (the home folder when nil): its absolute path,
    /// "#repo" if it's a git repo, then "#folders" and its folders
    /// ("./name"), then "#repos" and the `.git` of those that are repos
    /// ("./name/.git"). Exits 3 when it can't go in. No globs: the login
    /// shell may be zsh, which gives up on a command when one matches nothing.
    public static func folderCommand(path: String?) -> String {
        "\(goCommand(path)) 2>/dev/null || exit 3; pwd; [ -e .git ] && echo '#repo'; echo '#folders';"
            + " find -L . -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null; echo '#repos';"
            + " find -L . -mindepth 2 -maxdepth 2 -name .git 2>/dev/null; true"
    }

    /// Goes to `path`: the home folder when nil or "~", and "~/rest"
    /// under it (typed paths say "~").
    static func goCommand(_ path: String?) -> String {
        guard let path, path != "~" else { return "cd" }
        if path.hasPrefix("~/") { return "cd -- \"$HOME\"/\(shellQuote(String(path.dropFirst(2))))" }
        return "cd -- \(shellQuote(path))"
    }

    /// Folders searched below the one being browsed: no deeper than this.
    public static let searchDepth = 4
    /// Folders a search finds, at most.
    public static let searchLimit = 80

    /// Finds folders below `path` (as `folderCommand` takes it) whose
    /// names contain `keyword`, ignoring case: the shallowest first, at
    /// most `searchLimit`, no deeper than `searchDepth`, leaving out hidden
    /// folders and what's big and never a project (node_modules, Library,
    /// app bundles, build output). Prints the folder's absolute path, then
    /// "R ./a/b" for repos and "D ./a/b" for the rest. Exits 3 when it
    /// can't go in. nil when `keyword` has nothing to search for.
    public static func searchFoldersCommand(in path: String?, matching keyword: String) -> String? {
        // find's own wildcards would widen the match: plain text only.
        let text = keyword.filter { !"*?[]\\".contains($0) && !$0.isNewline }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let skip = [".*", "node_modules", "Library", "*.app", "DerivedData", "Pods", "build", "dist", "target", "venv"]
            .map { "-name \(shellQuote($0))" }.joined(separator: " -o ")
        return "\(goCommand(path)) 2>/dev/null || exit 3; pwd;"
            + " find -H . -mindepth 1 -maxdepth \(searchDepth) \\( \(skip) \\) -prune -o -type d -iname \(shellQuote("*\(text)*")) -print 2>/dev/null"
            + " | awk -F/ '{ print NF, $0 }' | sort -s -n -k1,1 | head -n \(searchLimit) | cut -d' ' -f2-"
            + " | while IFS= read -r p; do if [ -e \"$p/.git\" ]; then echo \"R $p\"; else echo \"D $p\"; fi; done; true"
    }

    /// `searchFoldersCommand` output; nil if it isn't that.
    public static func parseFolderSearch(_ output: String) -> FolderSearch? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let base = lines.first, base.hasPrefix("/") else { return nil }
        let hits = lines.dropFirst().compactMap { line -> FolderSearch.Hit? in
            guard line.count > 4, line.dropFirst(1).hasPrefix(" ./"), let kind = line.first, "RD".contains(kind) else { return nil }
            let relative = String(line.dropFirst(4))
            let parts = relative.split(separator: "/")
            guard !parts.isEmpty, !parts.contains(where: { $0.hasPrefix(".") }) else { return nil }
            return FolderSearch.Hit(path: (base == "/" ? "" : base) + "/" + relative, isRepo: kind == "R", depth: parts.count)
        }
        // The shallowest first; at one depth, by name.
        let ordered = hits.enumerated().sorted { a, b in
            a.element.depth != b.element.depth
                ? a.element.depth < b.element.depth
                : a.element.name.localizedStandardCompare(b.element.name) == .orderedAscending
        }.map(\.element)
        return FolderSearch(path: base, hits: ordered)
    }

    /// The models `agent` lists on the Mac, in its own order, one
    /// "id<tab>name" a line, after "#default<tab>id" for the one it starts
    /// with when given none (if it says); nothing when it has no list
    /// there. Claude Code keeps its model picker's catalog in
    /// ~/.claude/cache/model-catalog (the newest "…-cc.json"; its default
    /// is the catalog's state.model). Codex keeps its list in
    /// ~/.codex/models_cache.json (those it lists in its picker; its default
    /// is config.toml's top-level model). Read with plutil, which macOS has.
    public static func agentModelsCommand(_ agent: TerminalAgent) -> String {
        let find: String
        let models: String
        let id: String
        let name: String
        let byDefault: String
        var only = ""
        switch agent {
        case .claude:
            find = #"f=$(find "$HOME/.claude/cache/model-catalog" -maxdepth 1 -name '*-cc.json' -exec ls -t {} + 2>/dev/null | head -n 1)"#
            models = "catalog.config.models"
            id = "id"
            name = "name"
            byDefault = #"d=$(plutil -extract catalog.state.model raw -o - "$f" 2>/dev/null)"#
        case .codex:
            find = #"f="$HOME/.codex/models_cache.json""#
            models = "models"
            id = "slug"
            name = "display_name"
            // Up to its first [section]: the top-level model.
            byDefault = #"d=$(sed -n -e '/^\[/q' -e 's/^model *= *"\([^"]*\)".*/\1/p' "$HOME/.codex/config.toml" 2>/dev/null)"#
            only = #"[ "$(plutil -extract "$m.visibility" raw -o - "$f" 2>/dev/null)" = list ] || { i=$((i+1)); continue; };"#
        }
        return find + #"; [ -n "$f" ] || exit 0; n=$(plutil -extract \#(models) raw -o - "$f" 2>/dev/null) || exit 0;"#
            + #" \#(byDefault); [ -n "$d" ] && printf '#default\t%s\n' "$d"; i=0;"#
            + #" while [ "$i" -lt "$n" ]; do m="\#(models).$i"; \#(only)"#
            + #" printf '%s\t%s\n' "$(plutil -extract "$m.\#(id)" raw -o - "$f" 2>/dev/null)" "$(plutil -extract "$m.\#(name)" raw -o - "$f" 2>/dev/null)";"#
            + #" i=$((i+1)); done; true"#
    }

    /// `agentModelsCommand` output: the models in order, once each, names
    /// it could type only; and the default, by the Mac's word or else
    /// (Codex) its first.
    public static func parseAgentModels(_ output: String, for agent: TerminalAgent) -> AgentModelList {
        var seen = Set<String>()
        var defaultID: String?
        let models = output.split(separator: "\n").compactMap { line -> AgentModel? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.first == "#default" {
                defaultID = parts.count > 1 ? parts[1] : nil
                return nil
            }
            guard let id = parts.first, AgentModel.isName(id), seen.insert(id).inserted else { return nil }
            let name = parts.count > 1 && !parts[1].isEmpty ? parts[1] : id
            return AgentModel(id: id, name: name)
        }
        let named = defaultID.flatMap { id in models.first { $0.id == id } ?? (AgentModel.isName(id) ? AgentModel(id: id, name: id) : nil) }
        return AgentModelList(models: models, defaultModel: named ?? (agent == .codex ? models.first : nil))
    }

    /// `folderCommand` output; nil if it isn't that.
    public static func parseFolder(_ output: String) -> MacFolder? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let path = lines.first, path.hasPrefix("/"),
              let foldersAt = lines.firstIndex(of: "#folders"),
              let reposAt = lines.firstIndex(of: "#repos"), foldersAt < reposAt else { return nil }
        func name(_ line: String, dropping suffix: String = "") -> String? {
            guard line.hasPrefix("./"), line.hasSuffix(suffix) else { return nil }
            let name = String(line.dropFirst(2).dropLast(suffix.count))
            return name.isEmpty || name.contains("/") || name.hasPrefix(".") ? nil : name
        }
        let repos = Set(lines[(reposAt + 1)...].compactMap { name($0, dropping: "/.git") })
        var seen = Set<String>()
        let folders = lines[(foldersAt + 1)..<reposAt]
            .compactMap { name($0) }
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { MacFolder.Entry(name: $0, isRepo: repos.contains($0)) }
        return MacFolder(path: path, isRepo: lines[1..<foldersAt].contains("#repo"), folders: folders)
    }
}
