#if os(macOS)
import SwiftUI

/// A tickets panel's settings, in a popover from its title bar: whether
/// its project's tickets start by themselves, and the project's manager.
/// Outside every project it says where to put the panel. Edits apply as
/// they're made.
struct TicketBoardSettings: View {
    /// A terminal pane the Manager menu offers.
    struct Terminal: Hashable {
        let pane: UUID
        let title: String
    }

    /// The project the panel is in; nil outside every project.
    let project: CanvasZone?
    /// The project's terminals, its domains' included.
    let terminals: [Terminal]
    let update: ((inout CanvasZone) -> Void) -> Void

    @State private var autoStart: Bool
    @State private var manager: UUID?

    init(project: CanvasZone?, terminals: [Terminal], update: @escaping ((inout CanvasZone) -> Void) -> Void) {
        self.project = project
        self.terminals = terminals
        self.update = update
        _autoStart = State(initialValue: project?.autoStart == true)
        // A manager that's left the project shows as None until another's picked.
        _manager = State(initialValue: terminals.contains { $0.pane == project?.manager } ? project?.manager : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let project {
                section("Start") {
                    Toggle("Start tickets automatically", isOn: $autoStart)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    note(autoStart
                        ? "A queued ticket is typed into its feature's Claude as soon as that Claude is free."
                        : "A queued ticket waits for Start.")
                }
                section("Manager") {
                    Picker("Manager", selection: $manager) {
                        Text("None").tag(UUID?.none)
                        ForEach(terminals, id: \.pane) { terminal in
                            Text(terminal.title).tag(UUID?.some(terminal.pane))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    note("A terminal in \(project.name). Its Claude turns your requests into tickets with "
                        + "lostty +ticket add, and hears when one is blocked. Lostty types no tickets into it.")
                }
            } else {
                note("Put this panel in a project zone to start its tickets automatically and pick a manager.")
            }
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: autoStart) { _, value in update { $0.autoStart = value } }
        .onChange(of: manager) { _, value in update { $0.manager = value } }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
