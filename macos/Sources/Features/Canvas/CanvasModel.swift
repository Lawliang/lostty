#if os(macOS)
import CoreGraphics
import Foundation
import LosttyRemote

/// The canvas's cards: frames in document points (the canvas scroll view's
/// flipped document, `size` square, y down), back to front. Pure
/// geometry; CanvasController applies it to views.
struct CanvasModel: Equatable {
    struct Card: Equatable, Identifiable {
        let id: UUID
        var frame: CGRect
    }

    /// The card edges a resize drags.
    struct Edges: OptionSet, Hashable {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    enum Direction: CaseIterable { case left, right, up, down }

    /// The document is this wide and tall; the first cards go in its middle.
    static let size: CGFloat = 100_000
    static let middle = CGPoint(x: size / 2, y: size / 2)
    /// A new card's size, and the smallest a card can be, at 100%.
    static let newCardSize = CGSize(width: 720, height: 500)
    static let minimumCardSize = CGSize(width: 320, height: 200)
    /// How far a new card steps down and right off another's corner.
    static let nudge: CGFloat = 32
    /// The space between a card and one made beside it (⌘T): none, edge to
    /// edge.
    static let besideGap: CGFloat = 0
    /// The room round the cards when zooming to fit them.
    static let fitMargin: CGFloat = 40
    /// The resize strips along a card's edges, and the squares at its corners.
    static let handleThickness: CGFloat = 6
    static let handleCorner: CGFloat = 14
    static let handleEdges: [Edges] = [
        .left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom],
    ]

    /// Back to front: the last is drawn on top.
    private(set) var cards: [Card] = []

    func card(_ id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    mutating func add(_ id: UUID, frame: CGRect) {
        remove(id)
        cards.append(Card(id: id, frame: Self.clamped(frame)))
    }

    /// A card at `index` back to front (in front of every card past the end).
    mutating func insert(_ id: UUID, frame: CGRect, at index: Int) {
        remove(id)
        cards.insert(Card(id: id, frame: Self.clamped(frame)), at: min(max(index, 0), cards.count))
    }

    mutating func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
    }

    mutating func bringToFront(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards.append(cards.remove(at: index))
    }

    mutating func setFrame(_ frame: CGRect, of id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].frame = Self.clamped(frame)
    }

    /// The front-most card under `point`.
    func card(at point: CGPoint) -> UUID? {
        cards.last { $0.frame.contains(point) }?.id
    }

    /// Where a new card of `size` goes: centered in `visible`, stepped down
    /// and right while its top-left corner would sit on another card's.
    /// ⌘T: a card the size of card `id`, beside it: to its right, else
    /// below, left or above, the first side no card covers; else further
    /// right, past whatever is there. Nil without that card.
    func placement(beside id: UUID) -> CGRect? {
        guard let from = card(id)?.frame else { return nil }
        let across = from.width + Self.besideGap, down = from.height + Self.besideGap
        let sides = [CGPoint(x: across, y: 0), CGPoint(x: 0, y: down), CGPoint(x: -across, y: 0), CGPoint(x: 0, y: -down)]
            + (2...20).map { CGPoint(x: across * CGFloat($0), y: 0) }
        for side in sides {
            let spot = Self.clamped(from.offsetBy(dx: side.x, dy: side.y))
            // Sharing an edge isn't covering.
            if !cards.contains(where: { Self.overlap($0.frame, spot) }) { return spot }
        }
        return Self.clamped(from.offsetBy(dx: Self.nudge, dy: Self.nudge))
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let both = a.intersection(b)
        return !both.isNull && both.width > 0 && both.height > 0
    }

    func placement(size: CGSize = newCardSize, in visible: CGRect) -> CGRect {
        var frame = CGRect(
            x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
        while cards.contains(where: { abs($0.frame.minX - frame.minX) < 1 && abs($0.frame.minY - frame.minY) < 1 }) {
            frame = frame.offsetBy(dx: Self.nudge, dy: Self.nudge)
        }
        return Self.clamped(frame)
    }

    /// Where cards of `sizes` go when several windows move in at once: rows
    /// of them, edge to edge, about as many across as down, centered in
    /// the view, or right of every card already there if that would cover
    /// one. A single card goes where `placement(size:in:)` puts it.
    func placements(sizes: [CGSize], in visible: CGRect) -> [CGRect] {
        guard sizes.count > 1 else { return sizes.map { placement(size: $0, in: visible) } }
        let across = Int(Double(sizes.count).squareRoot().rounded(.up))
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if index > 0, index.isMultiple(of: across) {
                x = 0
                y += rowHeight + Self.besideGap
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + Self.besideGap
            rowHeight = max(rowHeight, size.height)
        }
        let block = frames.reduce(CGRect.null) { $0.union($1) }
        var origin = CGPoint(x: (visible.midX - block.width / 2).rounded(), y: (visible.midY - block.height / 2).rounded())
        if cards.contains(where: { Self.overlap($0.frame, CGRect(origin: origin, size: block.size)) }) {
            let taken = cards.reduce(CGRect.null) { $0.union($1.frame) }
            origin = CGPoint(x: taken.maxX + Self.besideGap, y: taken.minY)
        }
        return frames.map { Self.clamped($0.offsetBy(dx: origin.x, dy: origin.y)) }
    }

    /// `frame` at least the minimum size and inside the document.
    static func clamped(_ frame: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumCardSize.width), size)
        let height = min(max(frame.height, minimumCardSize.height), size)
        return CGRect(
            x: min(max(frame.minX, 0), size - width), y: min(max(frame.minY, 0), size - height),
            width: width, height: height)
    }

    /// `frame` with `edges` dragged by `delta` (y down). A dragged edge stops
    /// at the minimum size instead of pushing the card along.
    static func resized(_ frame: CGRect, edges: Edges, by delta: CGSize) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if edges.contains(.left) { minX = min(minX + delta.width, maxX - minimumCardSize.width) }
        if edges.contains(.right) { maxX = max(maxX + delta.width, minX + minimumCardSize.width) }
        if edges.contains(.top) { minY = min(minY + delta.height, maxY - minimumCardSize.height) }
        if edges.contains(.bottom) { maxY = max(maxY + delta.height, minY + minimumCardSize.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where the resize handle for `edges` sits in a card's `bounds` (y down):
    /// a strip along an edge between the corners, or a corner square.
    static func handleFrame(for edges: Edges, in bounds: CGRect) -> CGRect {
        let thick = handleThickness, corner = handleCorner
        let horizontal = edges.intersection([.left, .right]), vertical = edges.intersection([.top, .bottom])
        if !horizontal.isEmpty, !vertical.isEmpty {
            return CGRect(
                x: horizontal == .left ? 0 : bounds.width - corner, y: vertical == .top ? 0 : bounds.height - corner,
                width: corner, height: corner)
        }
        switch edges {
        case .left: return CGRect(x: 0, y: corner, width: thick, height: bounds.height - 2 * corner)
        case .right: return CGRect(x: bounds.width - thick, y: corner, width: thick, height: bounds.height - 2 * corner)
        case .top: return CGRect(x: corner, y: 0, width: bounds.width - 2 * corner, height: thick)
        default: return CGRect(x: corner, y: bounds.height - thick, width: bounds.width - 2 * corner, height: thick)
        }
    }

    /// What zooming to fit shows: every card, with a margin. nil with none.
    var fitRect: CGRect? {
        fitRect(of: Set(cards.map(\.id)))
    }

    /// What Zoom to Selection shows: cards `ids`, with a margin. nil with none.
    func fitRect(of ids: Set<UUID>) -> CGRect? {
        let frames = cards.filter { ids.contains($0.id) }.map(\.frame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
            .insetBy(dx: -Self.fitMargin, dy: -Self.fitMargin)
    }

    /// The cards a marquee over `rect` selects: every one it touches.
    func cards(touching rect: CGRect) -> Set<UUID> {
        Set(cards.filter { $0.frame.intersects(rect) }.map(\.id))
    }

    /// The space Tidy Up leaves between cards.
    static let tidyGap: CGFloat = 14

    /// How Tidy Up lays the selection out.
    enum Tidy: CaseIterable {
        case row, grid, column

        /// The next layout, round and round.
        var next: Tidy {
            let all = Self.allCases
            return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
        }

        /// How many cards go across: a grid fills across before down, so
        /// six cards make three across and two down.
        func across(_ count: Int) -> Int {
            switch self {
            case .row: count
            case .column: 1
            case .grid: Int(Double(count).squareRoot().rounded(.up))
            }
        }
    }

    /// Tidy Up: cards `ids` in rows of `layout.across` cards, `tidyGap`
    /// apart, each row as tall as its tallest card, from the leftmost one's
    /// left edge and the highest one's top. A row takes them left to right
    /// as they were, a column top to bottom, a grid in reading order.
    func tidied(_ ids: Set<UUID>, into layout: Tidy = .row) -> [UUID: CGRect] {
        let chosen = cards.filter { ids.contains($0.id) }
        guard let left = chosen.map(\.frame.minX).min(), let top = chosen.map(\.frame.minY).min() else { return [:] }
        let order = chosen.sorted { a, b in
            layout == .row
                ? (a.frame.minX, a.frame.minY) < (b.frame.minX, b.frame.minY)
                : (a.frame.minY, a.frame.minX) < (b.frame.minY, b.frame.minX)
        }
        let across = layout.across(order.count)
        var frames: [UUID: CGRect] = [:]
        var x = left, y = top, rowHeight: CGFloat = 0
        for (index, card) in order.enumerated() {
            if index > 0, index.isMultiple(of: across) {
                x = left
                y += rowHeight + Self.tidyGap
                rowHeight = 0
            }
            frames[card.id] = Self.clamped(CGRect(origin: CGPoint(x: x, y: y), size: card.frame.size))
            x += card.frame.width + Self.tidyGap
            rowHeight = max(rowHeight, card.frame.height)
        }
        return frames
    }

    /// The cards to draw live: those touching `visible` grown by half a new
    /// card each way, so panning never shows a stale frame.
    func cardsInView(_ visible: CGRect) -> Set<UUID> {
        let near = visible.insetBy(dx: -Self.newCardSize.width / 2, dy: -Self.newCardSize.height / 2)
        return Set(cards.filter { $0.frame.intersects(near) }.map(\.id))
    }

    /// The nearest card whose center lies within 45° of `direction` from
    /// `id`'s center, of those in `among` (every card when nil).
    func neighbor(of id: UUID, _ direction: Direction, among: Set<UUID>? = nil) -> UUID? {
        guard let from = card(id)?.frame else { return nil }
        var best: (id: UUID, distance: CGFloat)?
        for card in cards where card.id != id && among?.contains(card.id) != false {
            let dx = card.frame.midX - from.midX, dy = card.frame.midY - from.midY
            let (along, across): (CGFloat, CGFloat) = switch direction {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .up: (-dy, dx)
            case .down: (dy, dx)
            }
            guard along > 0, abs(across) <= along else { continue }
            let distance = dx * dx + dy * dy
            if best.map({ distance < $0.distance }) ?? true { best = (card.id, distance) }
        }
        return best?.id
    }
}

/// The canvas's zoom: its limits, and what a zoom shows.
enum CanvasZoom {
    static let minimum: CGFloat = 0.25
    static let maximum: CGFloat = 2
    /// No zoom change for this long and the terminals re-render at the new scale.
    static let settle: TimeInterval = 0.15

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minimum), maximum)
    }

    /// The document rect a `viewport` of screen points shows at `zoom`,
    /// centered on `center`.
    static func rect(centeredOn center: CGPoint, zoom: CGFloat, viewport: CGSize) -> CGRect {
        let zoom = clamped(zoom)
        let size = CGSize(width: viewport.width / zoom, height: viewport.height / zoom)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// A pane's pixels per point at `zoom` on a screen of `backing` scale:
    /// its content scale once a zoom settles. Its size in points doesn't
    /// change, so neither does its grid.
    static func contentScale(backing: CGFloat, zoom: CGFloat) -> CGFloat {
        backing * clamped(zoom)
    }
}

/// The dot grid behind the cards: a dot every `spacing` screen points.
enum CanvasGrid {
    /// The dots' spacing on screen, the same at every zoom: a square 14pt
    /// grid, denser than the Lostty website's.
    static let spacing = CGSize(width: 14, height: 14)

    /// Where the first dot sits on screen (the view's top-left at 0, 0) when
    /// the view shows the document from `origin` at `zoom`, so dots move
    /// with the canvas as it pans.
    static func firstDot(origin: CGPoint, zoom: CGFloat) -> CGPoint {
        func first(_ value: CGFloat, _ gap: CGFloat) -> CGFloat {
            let screen = value * zoom
            return (screen / gap).rounded(.up) * gap - screen
        }
        return CGPoint(x: first(origin.x, spacing.width), y: first(origin.y, spacing.height))
    }
}

/// The panes waiting on you (Ready for Response), oldest first, for Jump
/// to What Needs You.
struct CanvasWaits: Equatable {
    private(set) var since: [UUID: Date] = [:]

    /// Keeps when each waiting pane began waiting; forgets the rest, so a
    /// pane that waits again goes to the back.
    mutating func update(awaiting: Set<UUID>, now: Date) {
        since = since.filter { awaiting.contains($0.key) }
        for id in awaiting where since[id] == nil { since[id] = now }
    }

    /// Oldest first; panes that began together in a stable order.
    var order: [UUID] {
        since.sorted { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }.map(\.key)
    }

    /// The pane to jump to after `current`: the next waiting one of `panes`
    /// (the canvas's), round and round; the oldest when `current` isn't
    /// waiting.
    func next(after current: UUID?, among panes: Set<UUID>) -> UUID? {
        let waiting = order.filter(panes.contains)
        guard let first = waiting.first else { return nil }
        guard let current, let index = waiting.firstIndex(of: current) else { return first }
        return waiting[(index + 1) % waiting.count]
    }
}

/// What the canvas keeps across Restart to Update and relaunches: whether
/// it's shown, the view, each terminal card back to front, and the
/// tickets with their panel. Generic over the split tree, so tests can
/// save plain values.
struct CanvasSaved<Tree: Codable>: Codable {
    struct Card: Codable {
        var frame: CGRect
        var tree: Tree
        /// The card's focused pane, as a UUID string.
        var focused: String?
    }

    /// A ticket as its own card, as saved before the tickets panel: read so
    /// its ticket joins the panel, never written.
    struct Ticket: Codable, Equatable {
        var id: UUID
        var frame: CGRect
        var ticket: CanvasTicket
        /// The form's contents while it's open: a new ticket's, or unsaved
        /// edits. It opens again with them.
        var draft: CanvasTicket?
        /// Where it sat among every card, back to front.
        var stack: Int
    }

    /// The tickets, and their panel while it's open.
    struct Board: Codable, Equatable {
        var tickets: [CanvasTicket]
        /// The panel's frame and place among every card, back to front;
        /// nil while it's closed.
        var frame: CGRect?
        var stack: Int?
        /// The new ticket's sheet, open with what's typed in it.
        var draft: CanvasTicket?

        init(tickets: [CanvasTicket], frame: CGRect? = nil, stack: Int? = nil, draft: CanvasTicket? = nil) {
            self.tickets = tickets
            self.frame = frame
            self.stack = stack
            self.draft = draft
        }

        /// A ticket that can't be read is left out, never the rest.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tickets = c.decodeEach(CanvasTicket.self, forKey: .tickets) ?? []
            frame = try? c.decodeIfPresent(CGRect.self, forKey: .frame)
            stack = try? c.decodeIfPresent(Int.self, forKey: .stack)
            draft = try? c.decodeIfPresent(CanvasTicket.self, forKey: .draft)
        }
    }

    var visible: Bool
    var center: CGPoint
    var zoom: CGFloat
    var cards: [Card]
    /// Tickets saved as cards, before the panel; missing from a canvas
    /// saved before tickets, or since the panel.
    var tickets: [Ticket]?
    /// Missing from a canvas saved before the panel.
    var board: Board?

    /// Whether there's anything to bring back.
    var isEmpty: Bool {
        cards.isEmpty && (tickets ?? []).isEmpty && (board?.tickets ?? []).isEmpty && board?.draft == nil
    }

    init(visible: Bool, center: CGPoint, zoom: CGFloat, cards: [Card], tickets: [Ticket]? = nil, board: Board? = nil) {
        self.visible = visible
        self.center = center
        self.zoom = zoom
        self.cards = cards
        self.tickets = tickets
        self.board = board
    }

    /// Tickets that can't be read are left out, never the canvas with them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visible = try c.decode(Bool.self, forKey: .visible)
        center = try c.decode(CGPoint.self, forKey: .center)
        zoom = try c.decode(CGFloat.self, forKey: .zoom)
        cards = try c.decode([Card].self, forKey: .cards)
        tickets = c.decodeEach(Ticket.self, forKey: .tickets)
        board = try? c.decodeIfPresent(Board.self, forKey: .board)
    }
}

extension KeyedDecodingContainer {
    /// The list under `key` without the elements that can't be read; nil
    /// when there's no list.
    func decodeEach<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var read: [T] = []
        while !list.isAtEnd {
            let index = list.currentIndex
            if let element = try? list.decode(T.self) {
                read.append(element)
            } else {
                _ = try? list.decode(Unread.self)
                // Never stuck on one that can't be stepped past.
                if list.currentIndex == index { break }
            }
        }
        return read
    }
}

/// Steps past a list element that couldn't be read: having no fields, it
/// reads any value.
private struct Unread: Decodable {}

extension CanvasSaved: Equatable where Tree: Equatable {}
extension CanvasSaved.Card: Equatable where Tree: Equatable {}
#endif
