#if os(iOS)
import LosttyRemote
import SwiftUI

/// A new terminal on the Mac, asked for here: which project, and which
/// agent CLI starts in it (Claude, Codex, or none).
/// Any project is a browse through the Mac's folders away; those picked
/// before and those open terminals are in are under Recents.
struct NewTerminalSheet: View {
    let create: (NewTerminalRequest) -> Void
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    /// "browse" while browsing the Mac's folders, "agent" while choosing
    /// the agent.
    @State private var browsing: [String] = []
    @State private var folder: String?
    @AppStorage(AgentChoice.agentKey) private var agentChoice = AgentChoice.defaultAgent

    private var agent: TerminalAgent? { TerminalAgent(rawValue: agentChoice) }

    var body: some View {
        NavigationStack(path: $browsing) {
            form.navigationDestination(for: String.self) { route in
                if route == "agent" {
                    AgentScreen()
                } else {
                    FolderBrowser { picked in
                        folder = picked
                        browsing = []
                    }
                }
            }
        }
        .onDisappear { Task { await store.endBrowsing() } }
    }

    private var form: some View {
        Form {
            Section("Agent CLI") {
                NavigationLink(value: "agent") {
                    HStack {
                        Label(AgentChoice.name(agent), systemImage: AgentChoice.symbol(agent))
                            .foregroundStyle(LosttyTheme.textPrimary)
                        Spacer()
                        if let model = agent.flatMap(AgentChoice.model(for:)) {
                            Text(model.name).foregroundStyle(LosttyTheme.textSecondary)
                        }
                    }
                }
            }
            .listRowBackground(LosttyTheme.surface)
            Section("Select Project") {
                // Browsed to: here until it's a recent one.
                if let folder, !recents.contains(folder) { row(folder) }
                NavigationLink(value: "browse") {
                    Label("Browse your Mac…", systemImage: "folder")
                        .foregroundStyle(LosttyTheme.textPrimary)
                }
            }
            .listRowBackground(LosttyTheme.surface)
            if !recents.isEmpty {
                Section("Recents") {
                    ForEach(recents, id: \.self, content: row)
                }
                .listRowBackground(LosttyTheme.surface)
            }
        }
        .tint(LosttyTheme.accent)
        .navigationTitle("New Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .tint(.white)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    guard let folder else { return }
                    create(NewTerminalRequest(
                        folder: folder, agent: agent, agentOptions: agent.map(AgentChoice.options(for:)),
                        model: agent.flatMap(AgentChoice.model(for:))?.id))
                    dismiss()
                }
                .tint(.white)
                .disabled(folder == nil)
            }
        }
    }

    /// Those picked before, then those open terminals are in (not home
    /// folders).
    private var recents: [String] {
        var seen = Set<String>()
        let open = store.sessions.map(\.path).filter { $0.hasPrefix("/") && !Self.isHome($0) }
        return (store.recentProjects + open).filter { seen.insert($0).inserted }
    }

    private func row(_ path: String) -> some View {
        Button {
            folder = path
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((path as NSString).lastPathComponent)
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                    Text(Self.abbreviated(path))
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if folder == path {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(LosttyTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(folder == path ? .isSelected : [])
    }

    /// "/Users/me/projectrepos/lostty" → "~/projectrepos/lostty".
    static func abbreviated(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[1] == "Users" else { return path }
        return parts.count == 3 ? "~" : "~/" + parts.dropFirst(3).joined(separator: "/")
    }

    /// "/Users/me".
    static func isHome(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[1] == "Users"
    }
}

/// The agent a new terminal starts in, and each agent's options: kept
/// on the phone, so the next new terminal starts the same way.
enum AgentChoice {
    /// "claude", "codex"…, or "none" (a plain shell).
    static let agentKey = "LosttyNewTerminalAgent"
    static let defaultAgent = TerminalAgent.claude.rawValue

    /// The agent's chosen options' ids, comma-separated.
    static func optionsKey(_ agent: TerminalAgent) -> String { "LosttyNewTerminalAgentOptions.\(agent.rawValue)" }

    static func options(for agent: TerminalAgent) -> [String] {
        (UserDefaults.standard.string(forKey: optionsKey(agent)) ?? "").split(separator: ",").map(String.init)
    }

    /// The agent's chosen model as "id<tab>name"; none: its own default.
    static func modelKey(_ agent: TerminalAgent) -> String { "LosttyNewTerminalAgentModel.\(agent.rawValue)" }

    static func model(for agent: TerminalAgent) -> AgentModel? {
        decodeModel(UserDefaults.standard.string(forKey: modelKey(agent)) ?? "")
    }

    static func encode(_ model: AgentModel?) -> String { model.map { "\($0.id)\t\($0.name)" } ?? "" }

    static func decodeModel(_ stored: String) -> AgentModel? {
        let parts = stored.split(separator: "\t", maxSplits: 1).map(String.init)
        guard let id = parts.first, AgentModel.isName(id) else { return nil }
        return AgentModel(id: id, name: parts.count > 1 ? parts[1] : id)
    }

    static func name(_ agent: TerminalAgent?) -> String { agent?.name ?? "Shell" }

    static func symbol(_ agent: TerminalAgent?) -> String {
        switch agent {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case nil: "terminal"
        }
    }
}

/// Which agent CLI a new terminal starts in (or a plain shell), and the
/// chosen one's options.
private struct AgentScreen: View {
    @AppStorage(AgentChoice.agentKey) private var choice = AgentChoice.defaultAgent

    private var chosen: TerminalAgent? { TerminalAgent(rawValue: choice) }
    private var agents: [TerminalAgent?] { TerminalAgent.allCases.map(Optional.some) + [nil] }

    var body: some View {
        Form {
            Section("Agent CLI") {
                ForEach(agents, id: \.self) { agent in
                    Button {
                        withAnimation { choice = agent?.rawValue ?? "none" }
                    } label: {
                        HStack {
                            Label(AgentChoice.name(agent), systemImage: AgentChoice.symbol(agent))
                                .foregroundStyle(LosttyTheme.textPrimary)
                            Spacer()
                            if chosen == agent {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(LosttyTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen == agent ? .isSelected : [])
                }
            }
            .listRowBackground(LosttyTheme.surface)
            if let chosen {
                AgentModels(agent: chosen).id(chosen)
                if !chosen.options.isEmpty { AgentOptions(agent: chosen).id(chosen) }
            }
        }
        .tint(LosttyTheme.accent)
        .navigationTitle("Agent CLI")
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
    }
}

/// One agent's models: its own default first, then those it has (from
/// the Mac, for an agent that lists them there).
private struct AgentModels: View {
    let agent: TerminalAgent
    @EnvironmentObject private var store: MobileStore
    @AppStorage private var stored: String
    /// nil while asking the Mac.
    @State private var models: AgentModelList?
    @State private var failed = false

    init(agent: TerminalAgent) {
        self.agent = agent
        _stored = AppStorage(wrappedValue: "", AgentChoice.modelKey(agent))
    }

    private var chosen: AgentModel? { AgentChoice.decodeModel(stored) }

    /// The chosen one stays a choice even when the Mac no longer lists it.
    private var shown: [AgentModel] {
        let listed = models?.models ?? []
        guard let chosen, !listed.contains(where: { $0.id == chosen.id }) else { return listed }
        return listed + [chosen]
    }

    var body: some View {
        Section("Model") {
            row(nil)
            ForEach(shown) { row($0) }
            if models == nil {
                if failed {
                    Button("Couldn't get \(agent.name)'s models from your Mac. Try Again") { Task { await load() } }
                } else {
                    BufferSpinner(color: LosttyTheme.accent)
                        .frame(width: 18, height: 18)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Getting models")
                }
            }
        }
        .listRowBackground(LosttyTheme.surface)
        .task { if models == nil { await load() } }
    }

    private func row(_ model: AgentModel?) -> some View {
        let picked = chosen?.id == model?.id
        return Button {
            stored = AgentChoice.encode(model)
        } label: {
            HStack {
                Text(model?.name ?? defaultName).foregroundStyle(LosttyTheme.textPrimary)
                Spacer()
                if picked {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(LosttyTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// "Default (Opus 5.5)": what the agent starts with given no model.
    private var defaultName: String {
        models?.defaultModel.map { "Default (\($0.name))" } ?? "Default"
    }

    private func load() async {
        failed = false
        models = await store.agentModels(agent)
        failed = models == nil
    }
}

/// One agent's options, each a switch.
private struct AgentOptions: View {
    let agent: TerminalAgent
    @AppStorage private var chosen: String

    init(agent: TerminalAgent) {
        self.agent = agent
        _chosen = AppStorage(wrappedValue: "", AgentChoice.optionsKey(agent))
    }

    var body: some View {
        Section("\(agent.name) Options") {
            ForEach(agent.options) { option in
                Toggle(option.name, isOn: Binding(
                    get: { ids.contains(option.id) },
                    set: { on in
                        let next = on ? ids.union([option.id]) : ids.subtracting([option.id])
                        // In the agent's order, so the stored value is stable.
                        chosen = agent.options.map(\.id).filter(next.contains).joined(separator: ",")
                    }))
            }
        }
        .listRowBackground(LosttyTheme.surface)
    }

    private var ids: Set<String> { Set(chosen.split(separator: ",").map(String.init)) }
}

/// The Mac's folders, for the new terminal's project, on one screen: a
/// folder opens in place (only the grid changes). Where it is shows in a
/// path bar, each folder on the way a tap back up; the folders in it are a
/// grid of icons, as Finder shows them (a tap opens one; touch and hold to
/// use it); and a search: a name finds folders anywhere below, the
/// shallowest first; a path ("~/…" or "/…") lists that folder, narrowed
/// to what's typed after its last "/".
struct FolderBrowser: View {
    let pick: (String) -> Void
    @EnvironmentObject private var store: MobileStore
    /// The folder open: nil is the home folder; typed ones may start "~/".
    @State private var path: String?
    /// Folders seen here, by how they were opened: shown at once when
    /// opened again, while they're looked at afresh.
    @State private var seen: [String: MacFolder] = [:]
    @State private var look: MobileStore.FolderLook?
    @State private var query = ""
    @State private var found: Found?
    @FocusState private var searching: Bool

    /// What the search shows, once it has looked.
    enum Found: Equatable {
        /// A typed path's folder, narrowed to names starting `prefix`.
        case folder(MacFolder, prefix: String)
        case search(FolderSearch)
        case missing
        case failed(String)
    }

    /// One folder in the grid.
    struct Item: Identifiable, Equatable {
        var path: String
        var isRepo: Bool
        /// Where it is below the folder searched, for a search's.
        var within: String?
        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
    }

    private var current: MacFolder? {
        if case .found(let folder) = look { return folder }
        return nil
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 10) {
            searchBar
            pathBar
            // A new one for each folder: it opens at the top.
            ScrollView { content }
                .scrollDismissesKeyboard(.immediately)
                .id(path ?? "~")
                .animation(.easeOut(duration: 0.15), value: current?.path)
        }
        .padding(.top, 6)
        .navigationTitle("Select Project")
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .toolbar {
            if let current {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { pick(current.path) }
                        .tint(.white)
                        .accessibilityLabel("Use This Folder")
                }
            }
        }
        .task(id: path) { await load() }
        .task(id: trimmed) { await search(trimmed) }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(LosttyTheme.textSecondary)
            TextField("Search or Type Directory Path", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($searching)
                .onSubmit(openTyped)
            if !trimmed.isEmpty && found == nil {
                BufferSpinner(color: LosttyTheme.accent).frame(width: 14, height: 14)
            }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(LosttyTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LosttyTheme.surface))
        .padding(.horizontal, 16)
    }

    /// "~/…" or "/…": a path, not a name.
    static func isPath(_ text: String) -> Bool { text.hasPrefix("/") || text.hasPrefix("~") }

    /// A typed path's folder and what's typed after its last "/":
    /// "~/projectrepos/lo" → ("~/projectrepos", "lo").
    static func split(typed text: String) -> (folder: String, prefix: String) {
        guard let slash = text.lastIndex(of: "/") else { return (text, "") }
        let folder = String(text[..<slash])
        return (folder.isEmpty ? "/" : folder, String(text[text.index(after: slash)...]))
    }

    private func search(_ text: String) async {
        found = nil
        guard !text.isEmpty else { return }
        // Typing: wait for a pause.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let result: Found
        if Self.isPath(text) {
            let typed = Self.split(typed: text)
            switch await store.folder(at: typed.folder) {
            case .found(let folder): result = .folder(folder, prefix: typed.prefix)
            case .missing: result = .missing
            case .failed(let why): result = .failed(why)
            }
        } else {
            switch await store.searchFolders(in: current?.path ?? path, matching: text) {
            case .found(let search): result = .search(search)
            case .missing: result = .missing
            case .failed(let why): result = .failed(why)
            }
        }
        guard !Task.isCancelled else { return }
        found = result
    }

    /// Return on a typed path: into that folder.
    private func openTyped() {
        guard Self.isPath(trimmed) else { return }
        let target = trimmed.count > 1 && trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        open(target == "~" ? nil : target)
    }

    /// Opens folder `target` (nil: the home folder) in place.
    private func open(_ target: String?) {
        searching = false
        query = ""
        path = target
    }

    // MARK: Where

    /// The path bar's folders, home ("~") or "/" first; each but the
    /// last goes back to it.
    static func crumbs(of path: String) -> [(label: String, target: String?)] {
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Users" {
            let home = "/Users/" + parts[1]
            var crumbs: [(label: String, target: String?)] = [("~", nil)]
            for at in parts.indices.dropFirst(2) {
                crumbs.append((parts[at], home + "/" + parts[2...at].joined(separator: "/")))
            }
            return crumbs
        }
        var crumbs: [(label: String, target: String?)] = [("/", "/")]
        for at in parts.indices {
            crumbs.append((parts[at], "/" + parts[0...at].joined(separator: "/")))
        }
        return crumbs
    }

    private var pathBar: some View {
        let shown = current?.path ?? path ?? "~"
        let crumbs = shown.hasPrefix("/") ? Self.crumbs(of: shown) : [(label: shown, target: Optional(shown))]
        let trail = HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.footnote)
                .foregroundStyle(FolderIcon.blue)
            ForEach(crumbs.indices, id: \.self) { at in
                if at > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LosttyTheme.textSecondary.opacity(0.7))
                }
                let last = at == crumbs.count - 1
                Button(crumbs[at].label) { open(crumbs[at].target) }
                    .buttonStyle(.plain)
                    .font(LosttyFont.mono(.footnote, size: 14).weight(last ? .semibold : .regular))
                    .foregroundStyle(last ? LosttyTheme.textPrimary : LosttyTheme.textSecondary)
                    .allowsHitTesting(!last)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        // From the left while it fits; a long one scrolls, its end in view.
        return ViewThatFits(in: .horizontal) {
            trail.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) { trail }
                .defaultScrollAnchor(.trailing)
        }
        // Its folder icon under the search bar's magnifying glass.
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current folder, \(NewTerminalSheet.abbreviated(shown))")
    }

    // MARK: Folders

    @ViewBuilder private var content: some View {
        if trimmed.isEmpty {
            switch look {
            case nil: waiting
            case .missing: note("This folder isn't on your Mac anymore, or can't be opened.")
            case .failed(let why): failed(why)
            case .found(let folder):
                if folder.folders.isEmpty {
                    note(folder.isRepo ? "No folders in here. Use it with Use, above." : "No folders in here.")
                } else {
                    grid(folder.folders.map { Item(path: folder.path(of: $0.name), isRepo: $0.isRepo) })
                }
            }
        } else {
            switch found {
            case nil: waiting
            case .missing: note("There's no folder at \(trimmed).")
            case .failed(let why): failed(why)
            case .folder(let folder, let prefix):
                let items = folder.folders
                    .filter { prefix.isEmpty || $0.name.lowercased().hasPrefix(prefix.lowercased()) }
                    .map { Item(path: folder.path(of: $0.name), isRepo: $0.isRepo) }
                if items.isEmpty { note("No folders there start with \"\(prefix)\".") } else { grid(items) }
            case .search(let search):
                let items = search.hits.map { hit in
                    Item(path: hit.path, isRepo: hit.isRepo, within: Self.within(hit.path, below: search.path))
                }
                if items.isEmpty { note("No folders named like \"\(trimmed)\" in here.") } else { grid(items) }
            }
        }
    }

    /// The folders between `base` and the one at `path`: "code/apps" for
    /// "<base>/code/apps/lostty"; nil when it's directly in `base`.
    static func within(_ path: String, below base: String) -> String? {
        let prefix = base == "/" ? "/" : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let parent = (String(path.dropFirst(prefix.count)) as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private func grid(_ items: [Item]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82, maximum: 120), spacing: 6, alignment: .top)], spacing: 14) {
            ForEach(items) { cell($0) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private func cell(_ item: Item) -> some View {
        Button {
            open(item.path)
        } label: {
            VStack(spacing: 5) {
                FolderIcon(isRepo: item.isRepo).frame(width: 62, height: 50)
                Text(item.name)
                    .font(.footnote)
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let within = item.within {
                    Text(within)
                        .font(.caption2)
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                pick(item.path)
            } label: {
                Label("Use \(item.name)", systemImage: "checkmark.circle")
            }
            Button {
                open(item.path)
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
        .accessibilityLabel(item.isRepo ? "\(item.name), git repo" : item.name)
        .accessibilityHint("Opens the folder")
        .accessibilityAction(named: "Use \(item.name)") { pick(item.path) }
    }

    private var waiting: some View {
        BufferSpinner(color: LosttyTheme.accent)
            .frame(width: 22, height: 22)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Looking on your Mac")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(LosttyFont.body)
            .foregroundStyle(LosttyTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 60)
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: 12) {
            note(why)
            Button("Try Again") {
                Task {
                    await load()
                    await search(trimmed)
                }
            }
            .buttonStyle(.lostty(.secondary))
        }
    }

    private func load() async {
        let key = path ?? "~"
        look = seen[key].map(MobileStore.FolderLook.found)
        let fresh = await store.folder(at: path)
        // Opened another meanwhile: that one's look is coming.
        guard !Task.isCancelled, (path ?? "~") == key else { return }
        if case .found(let folder) = fresh { seen[key] = folder }
        // Seen before and unreachable now: keep showing what was seen.
        if case .failed = fresh, look != nil { return }
        look = fresh
    }
}

/// A folder as Finder draws one, with a branch badge on git repos.
struct FolderIcon: View {
    static let blue = Color(red: 0.42, green: 0.71, blue: 0.96)

    let isRepo: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Self.blue.gradient)
            if isRepo {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LosttyTheme.accent))
                    .overlay(Circle().strokeBorder(LosttyTheme.background, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A terminal being made on the Mac from here: the axolotl waits (as it
/// does while a terminal opens) until the Mac answers; then the terminal
/// takes its place, or what went wrong shows.
struct CreatingTerminalScreen: View {
    let request: NewTerminalRequest
    let opened: (RemoteSession) -> Void
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    var body: some View {
        Group {
            if let failure {
                UhOh(headline: "Couldn't make the terminal", detail: failure) {
                    Button("OK") { dismiss() }
                        .buttonStyle(.lostty(.primary, fullWidth: true))
                }
            } else {
                TerminalLoading(skin: nil, label: request.branch.map { "Making \($0)" } ?? "Opening the terminal")
            }
        }
        .navigationTitle((request.folder as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            switch await store.createTerminal(request) {
            case .success(let session): opened(session)
            case .failure(let failure): self.failure = failure.message
            }
        }
    }
}
#endif
