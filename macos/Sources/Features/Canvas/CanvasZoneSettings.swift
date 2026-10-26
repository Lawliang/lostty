#if os(macOS)
import AppKit
import SwiftUI

/// A zone's settings, in a popover from its label: name, color, folder,
/// brief, a project's ticket key prefix and whether its tickets start
/// by themselves, what's inside and the boundary's rules. Edits apply as
/// they're made.
struct CanvasZoneSettings: View {
    /// A domain's project; nil for a project.
    let project: CanvasZone?
    /// The titles of the cards inside, as their headers show them.
    let members: [String]
    let update: ((inout CanvasZone) -> Void) -> Void
    let zoomToZone: () -> Void
    let remove: () -> Void

    @State private var name: String
    @State private var color: CanvasZone.Color
    @State private var folder: String
    @State private var brief: String
    @State private var keyPrefix: String
    @State private var autoStart: Bool
    @State private var pickedOutside = false

    init(
        zone: CanvasZone, project: CanvasZone?, members: [String],
        update: @escaping ((inout CanvasZone) -> Void) -> Void,
        zoomToZone: @escaping () -> Void, remove: @escaping () -> Void
    ) {
        self.project = project
        self.members = members
        self.update = update
        self.zoomToZone = zoomToZone
        self.remove = remove
        _name = State(initialValue: zone.name)
        _color = State(initialValue: zone.color)
        _folder = State(initialValue: zone.folder ?? "")
        _brief = State(initialValue: zone.brief)
        _keyPrefix = State(initialValue: zone.keyPrefix ?? "")
        _autoStart = State(initialValue: zone.autoStart == true)
    }

    private var isDomain: Bool { project != nil }
    private var prefix: String {
        CanvasZone(id: UUID(), frame: .zero, name: name, keyPrefix: keyPrefix).ticketPrefix
    }
    private var projectFolder: String? {
        project?.folder.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            section("Color") { swatches }
            section(isDomain ? "Subfolder" : "Folder") { folderRow }
            section("Brief") {
                TextEditor(text: $brief)
                    .font(.system(size: 12))
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                if !isDomain {
                    note("""
                        Optional: CLAUDE.md or AGENTS.md already describes the project. \
                        This is for what's true on your desk, like "test Stripe in test mode only".
                        """)
                }
            }
            if !isDomain {
                section("Ticket key prefix") {
                    TextField(CanvasZone.defaultTicketPrefix(name), text: $keyPrefix)
                        .textFieldStyle(.roundedBorder)
                    note("Tickets made here and in its domains: \(prefix)-1, \(prefix)-2…")
                }
                section("Tickets") {
                    Toggle("Start tickets automatically", isOn: $autoStart)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    note(autoStart
                        ? "A queued ticket is typed into its domain's Claude as soon as that Claude is free."
                        : "A queued ticket waits for Start on the board.")
                }
            }
            section("Inside") { inside }
            section("Boundary") { note(boundary) }
            Divider()
            HStack {
                Button("Zoom to Zone", action: zoomToZone)
                Spacer()
                Button("Remove Zone", role: .destructive, action: remove)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: name) { _, value in update { $0.name = value } }
        .onChange(of: color) { _, value in update { $0.color = value } }
        .onChange(of: folder) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            update { $0.folder = trimmed.isEmpty ? nil : trimmed }
        }
        .onChange(of: brief) { _, value in update { $0.brief = value } }
        .onChange(of: autoStart) { _, value in update { $0.autoStart = value } }
        .onChange(of: keyPrefix) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            update { $0.keyPrefix = trimmed.isEmpty ? nil : trimmed }
        }
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(CanvasZone.Color.allCases, id: \.self) { swatch in
                Button { color = swatch } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.pill))
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(
                            Color(nsColor: swatch.tint), lineWidth: swatch == color ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(swatch.rawValue.capitalized)
                .accessibilityLabel(swatch.rawValue.capitalized)
            }
        }
    }

    @ViewBuilder private var folderRow: some View {
        HStack(spacing: 6) {
            TextField(isDomain ? "In the project's folder" : "None", text: $folder)
                .textFieldStyle(.roundedBorder)
                .disabled(isDomain && projectFolder == nil)
            Button("Choose…", action: choose)
                .disabled(isDomain && projectFolder == nil)
        }
        if isDomain, projectFolder == nil {
            note("Set \(project?.name ?? "the project")'s folder first.")
        } else if pickedOutside, let projectFolder {
            note("Pick a folder inside \(projectFolder).", warning: true)
        } else {
            note(isDomain ? "New terminals here start in it." : "New terminals in this zone start here.")
        }
    }

    @ViewBuilder private var inside: some View {
        if members.isEmpty {
            note("Nothing yet.")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(members.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var boundary: String {
        let reach = isDomain
            ? "Agents here see and message only agents in \(project?.name ?? "its project") and its domains."
            : "Agents in this zone see and message only agents in it, its domains included."
        return reach + " This covers Lostty's own channels only. It doesn't cover tmux (any process can still run "
            + "tmux -L lostty send-keys) or anything outside Lostty."
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func note(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(warning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A project picks any folder, kept with a tilde; a domain picks one in
    /// its project's folder, kept relative to it.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        let start = isDomain ? projectFolder : folder.isEmpty ? nil : folder
        if let start { panel.directoryURL = URL(fileURLWithPath: (start as NSString).expandingTildeInPath) }
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        guard isDomain else {
            pickedOutside = false
            folder = (path as NSString).abbreviatingWithTildeInPath
            return
        }
        guard let projectFolder, let sub = CanvasModel.subfolder(path, of: projectFolder) else {
            pickedOutside = true
            return
        }
        pickedOutside = false
        folder = sub
    }
}
#endif
