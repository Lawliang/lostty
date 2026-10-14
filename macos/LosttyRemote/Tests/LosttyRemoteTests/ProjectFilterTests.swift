import Testing
@testable import LosttyRemote

struct ProjectFilterTests {
    private func row(_ id: String, _ project: String) -> SessionRow {
        SessionRow(id: id, title: id, project: project, branch: nil, kind: .shell, openOnMac: true,
                   status: .ready, skin: nil, action: nil, spinner: nil)
    }

    @Test func countsEachProjectsTerminalsAToZ() {
        let projects = ProjectFilter.projects([
            row("$1", "lostty"), row("$2", "hustleberry"), row("$3", "lostty"), row("$4", "Atlas"),
        ])
        #expect(projects.map(\.name) == ["Atlas", "hustleberry", "lostty"])
        #expect(projects.map(\.count) == [1, 1, 2])
    }

    @Test func noTerminalsNoProjects() {
        #expect(ProjectFilter.projects([]).isEmpty)
    }
}
