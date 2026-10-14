import Foundation

/// A project with open terminals, for the list's Projects pills.
public struct OpenProject: Equatable, Sendable {
    public var name: String
    /// How many open terminals are in it.
    public var count: Int
    /// The first one's skin, for the pill's ">".
    public var skin: SessionSkin?
}

public enum ProjectFilter {
    /// The projects `rows` belong to, A to Z, with how many each.
    public static func projects(_ rows: [SessionRow]) -> [OpenProject] {
        var found: [String: OpenProject] = [:]
        for row in rows {
            found[row.project, default: OpenProject(name: row.project, count: 0, skin: row.skin)].count += 1
        }
        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
