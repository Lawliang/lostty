#if os(macOS)
import AppKit
import SwiftUI

/// A ticket's type: a white glyph on a rounded square of its color, as
/// Jira draws one.
struct TicketKindBadge: View {
    let kind: CanvasTicket.Kind
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(kind.color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.glyph)
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(kind.title)
    }
}

/// A ticket's status: an empty ring, half filled, or checked.
struct TicketStatusIcon: View {
    let status: CanvasTicket.Status
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(status.color)
            .frame(width: 16, height: 16)
            .accessibilityLabel(status.title)
    }
}

struct TicketPriorityIcon: View {
    let priority: CanvasTicket.Priority

    var body: some View {
        Image(systemName: priority.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(priority.color)
            .frame(width: 16, height: 16)
            .accessibilityLabel("\(priority.title) priority")
    }
}

/// The assignee's initials in a circle of a color their name picks; a
/// dashed outline of a person when there's none.
struct TicketAvatar: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        let initials = Self.initials(name)
        if initials.isEmpty {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
                .accessibilityLabel("Unassigned")
        } else {
            Text(initials)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Self.color(for: name), in: Circle())
                .accessibilityLabel(name)
        }
    }

    /// The first letters of the first two words.
    static func initials(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map { $0.uppercased() }.joined()
    }

    /// The same color for a name every launch (not `hashValue`, which changes).
    static func color(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }

    private static let palette = [
        Color(hex: 0x6E7BF2), Color(hex: 0xDC6B37), Color(hex: 0x34A083),
        Color(hex: 0xC2539B), Color(hex: 0x4F8FD6), Color(hex: 0xA7843B),
    ]
}

/// A key on the keyboard, for the panel's hints.
struct TicketKeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.17), lineWidth: 0.5))
    }
}

extension CanvasTicket.Kind {
    var glyph: String {
        switch self {
        case .task: "checkmark"
        case .bug: "ladybug.fill"
        case .story: "bookmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .task: Color(light: 0x2D7FF9, dark: 0x4C9AFF)
        case .bug: Color(light: 0xE5493A, dark: 0xF0634F)
        case .story: Color(light: 0x45A348, dark: 0x5BBE5E)
        }
    }

    /// For menus, which take an image, not a view.
    var menuImage: NSImage? {
        let symbol = switch self {
        case .task: "checkmark.square.fill"
        case .bug: "ladybug.fill"
        case .story: "bookmark.square.fill"
        }
        return NSImage.ticketSymbol(symbol, color: color)
    }
}

/// Jira's chevrons for each.
extension CanvasTicket.Priority {
    var symbol: String {
        switch self {
        case .highest: "chevron.up.2"
        case .high: "chevron.up"
        case .medium: "equal"
        case .low: "chevron.down"
        case .lowest: "chevron.down.2"
        }
    }

    var color: Color {
        switch self {
        case .highest: Color(light: 0xE0412F, dark: 0xFF6A55)
        case .high: Color(light: 0xEE6A33, dark: 0xFF8A4C)
        case .medium: Color(light: 0xE09A10, dark: 0xF2B330)
        case .low: Color(light: 0x2D7FF9, dark: 0x4C9AFF)
        case .lowest: Color(light: 0x6AA8F7, dark: 0x82B7FF)
        }
    }

    var menuImage: NSImage? { NSImage.ticketSymbol(symbol, color: color) }
}

extension CanvasTicket.Status {
    var symbol: String {
        switch self {
        case .toDo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .toDo: Color(light: 0x8E8E96, dark: 0x8E8E96)
        case .inProgress: Color(light: 0xDDA000, dark: 0xF2B800)
        case .done: Color(light: 0x5E5CE6, dark: 0x7D7AFF)
        }
    }

    var menuImage: NSImage? { NSImage.ticketSymbol(symbol, color: color) }
}

extension Color {
    /// `light` in light mode and `dark` in dark, as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    fileprivate init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension NSImage {
    /// An SF Symbol in `color`, for a menu item.
    static func ticketSymbol(_ name: String, color: Color) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [NSColor(color)]))
    }
}
#endif
