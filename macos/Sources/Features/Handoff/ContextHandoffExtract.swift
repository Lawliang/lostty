#if os(macOS)
import Foundation

/// The handoff an agent wrote at a clean break (spec §1).
struct ContextHandoff: Equatable {
    /// `continueWork`: the fresh agent carries on. `wait`: it was waiting
    /// on the user, so the fresh agent restates the question and waits.
    enum Next: String, Codable, Equatable {
        case continueWork, wait
    }

    /// The block's contents, without its tags.
    var text: String
    var next: Next
    /// The first line of "Where we are", for the bubble.
    var summary: String
}

/// Why a reply's handoff wasn't taken: there was none, or it lacked a
/// required section (its name, for the next directive).
enum ContextHandoffProblem: Error, Equatable {
    case none
    case missing(String)
}

/// Reads the agent's handoff: the file the directive names, else (agents
/// told before the file, or that couldn't write it) the
/// `<lostty-handoff>` block at the end of its reply.
enum ContextHandoffExtract {
    static let open = "<lostty-handoff>"
    static let close = "</lostty-handoff>"
    static let summaryMax = 80
    /// How the directive's template fills "Where we are".
    static let placeholder = "(done, with commits"

    /// The last block outside a code fence, if it has every required
    /// section (see `check`).
    static func find(in reply: String) -> Result<ContextHandoff, ContextHandoffProblem> {
        guard let body = lastBlock(reply) else { return .failure(.none) }
        return check(body)
    }

    /// A handoff file's text: the sections, with any tag lines dropped.
    /// An empty file is none.
    static func parse(file: String) -> Result<ContextHandoff, ContextHandoffProblem> {
        let body = file.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { ![open, close].contains($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .failure(.none) }
        return check(body)
    }

    /// Every required section: Where we are, Active workflow, Next
    /// (missing = wait), and with wait, Open threads.
    private static func check(_ body: String) -> Result<ContextHandoff, ContextHandoffProblem> {
        let sections = sections(body)
        // The directive's own template, echoed back, is no handoff.
        if (sections["Where we are"] ?? "").hasPrefix(placeholder) { return .failure(.none) }
        for name in ["Where we are", "Active workflow"] where (sections[name] ?? "").isEmpty {
            return .failure(.missing(name))
        }
        let nextWord = (sections["Next"] ?? "").lowercased()
        let next: ContextHandoff.Next = nextWord.hasPrefix("continue") ? .continueWork : .wait
        if next == .wait, (sections["Open threads"] ?? "").isEmpty { return .failure(.missing("Open threads")) }
        let firstLine = (sections["Where we are"] ?? "").split(separator: "\n").first.map(String.init) ?? ""
        return .success(ContextHandoff(text: body, next: next, summary: String(firstLine.prefix(summaryMax))))
    }

    /// The text between the last open and close tag lines that sit outside
    /// a ``` or ~~~ fence; nil without a closed block, or when anything
    /// but blank lines follows it (the handoff ends the reply).
    private static func lastBlock(_ reply: String) -> String? {
        var fenced = false
        var current: [Substring]?
        var last: [Substring]?
        for line in reply.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current != nil {
                if trimmed == close {
                    last = current
                    current = nil
                } else {
                    current?.append(line)
                }
                continue
            }
            if last != nil, !trimmed.isEmpty { last = nil }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenced.toggle()
            } else if !fenced, trimmed == open {
                current = []
            }
        }
        return last.map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// "## Name" headings and the trimmed text under each.
    private static func sections(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        var name: String?
        var lines: [Substring] = []
        func flush() {
            if let name { result[name] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                flush()
                name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                lines = []
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }
}
#endif
