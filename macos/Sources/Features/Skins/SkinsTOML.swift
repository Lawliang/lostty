#if os(macOS)
import Foundation

/// A scalar value in skins.toml.
enum TOMLValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

/// One `[table]` or `[[array-of-tables]]` block, or the implicit root block.
struct TOMLSection: Equatable {
    var path: [String]
    var isArrayElement: Bool
    var values: [String: TOMLValue]
    var line: Int
}

struct TOMLError: Error, Equatable, CustomStringConvertible {
    let line: Int
    let message: String
    var description: String { "skins.toml line \(line): \(message)" }
}

/// Parses the subset of TOML that skins.toml uses: `#` comments, `[a.b]` tables,
/// `[[a]]` arrays of tables, and `key = "string" | number | true | false`.
/// Inline tables, arrays, multi-line strings and dates are rejected.
enum SkinsTOML {
    static func parse(_ text: String) throws -> [TOMLSection] {
        var sections = [TOMLSection(path: [], isArrayElement: false, values: [:], line: 0)]
        var seenTables = Set<[String]>()
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let number = index + 1
            let line = stripComment(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]"), line.count > 4 else {
                    throw TOMLError(line: number, message: "malformed [[table]] header")
                }
                let path = try keyPath(String(line.dropFirst(2).dropLast(2)), line: number)
                sections.append(TOMLSection(path: path, isArrayElement: true, values: [:], line: number))
            } else if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count > 2 else {
                    throw TOMLError(line: number, message: "malformed [table] header")
                }
                let path = try keyPath(String(line.dropFirst().dropLast()), line: number)
                guard seenTables.insert(path).inserted else {
                    throw TOMLError(line: number, message: "duplicate table [\(path.joined(separator: "."))]")
                }
                sections.append(TOMLSection(path: path, isArrayElement: false, values: [:], line: number))
            } else {
                guard let eq = line.firstIndex(of: "=") else {
                    throw TOMLError(line: number, message: "expected key = value")
                }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                guard isBareKey(key) else {
                    throw TOMLError(line: number, message: "invalid key '\(key)'")
                }
                let valueText = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                let value = try parseValue(valueText, line: number)
                guard sections[sections.count - 1].values[key] == nil else {
                    throw TOMLError(line: number, message: "duplicate key '\(key)'")
                }
                sections[sections.count - 1].values[key] = value
            }
        }
        return sections
    }

    static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_" || $0 == "-"
        }
    }

    private static func keyPath(_ text: String, line: Int) throws -> [String] {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.allSatisfy(isBareKey) else {
            throw TOMLError(line: line, message: "invalid table name '\(text)'")
        }
        return parts
    }

    /// Removes a `# comment` that is not inside a string.
    private static func stripComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        for (offset, ch) in line.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "#" {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    private static func parseValue(_ text: String, line: Int) throws -> TOMLValue {
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if text.hasPrefix("\"") { return .string(try parseString(text, line: line)) }
        if !text.hasPrefix("+"), text.rangeOfCharacter(from: .letters) == nil, let number = Double(text) {
            return .number(number)
        }
        throw TOMLError(line: line, message: "unsupported value '\(text)'")
    }

    private static func parseString(_ text: String, line: Int) throws -> String {
        var result = ""
        var iterator = text.dropFirst().makeIterator()
        while let ch = iterator.next() {
            switch ch {
            case "\"":
                guard iterator.next() == nil else {
                    throw TOMLError(line: line, message: "unexpected text after string")
                }
                return result
            case "\\":
                switch iterator.next() {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: throw TOMLError(line: line, message: "unsupported escape in string")
                }
            default:
                result.append(ch)
            }
        }
        throw TOMLError(line: line, message: "unterminated string")
    }
}
#endif
