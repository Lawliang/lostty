import Foundation

/// Lostty Mobile's notifications (🔔): what the Mac keeps in
/// `notifications/notes.json` and the phone shows in its inbox. A terminal
/// waiting on you, or a new build to install.
public struct LosttyNote: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case waiting
        case build
    }

    public var id: UUID
    public var kind: Kind
    public var created: Date
    /// Last time it said something new: newest first in the inbox.
    public var updated: Date
    public var read: Bool
    public var title: String
    public var body: String
    /// The terminal it came from ("$3"); nil for a build shipped outside Lostty.
    public var sessionID: String?
    /// That terminal's `@lostty_skin`, so the note wears its colors.
    public var skin: String?
    public var build: NoteBuild?

    public init(
        id: UUID, kind: Kind, created: Date, updated: Date, read: Bool = false, title: String, body: String,
        sessionID: String? = nil, skin: String? = nil, build: NoteBuild? = nil
    ) {
        self.id = id
        self.kind = kind
        self.created = created
        self.updated = updated
        self.read = read
        self.title = title
        self.body = body
        self.sessionID = sessionID
        self.skin = skin
        self.build = build
    }
}

/// A phone build published over Tailscale (`ship-phone.sh`, `ship-ios.sh`).
public struct NoteBuild: Codable, Equatable, Sendable {
    public var app: String
    public var bundleID: String
    public var build: String
    public var commit: String
    public var branch: String
    public var project: String
    /// The `itms-services` link that starts the install.
    public var installURL: String

    public init(app: String, bundleID: String, build: String, commit: String, branch: String, project: String, installURL: String) {
        self.app = app
        self.bundleID = bundleID
        self.build = build
        self.commit = commit
        self.branch = branch
        self.project = project
        self.installURL = installURL
    }
}

/// The notes and every rule about them, shared by the Mac (which keeps
/// them) and the phone (which shows them and applies its own changes at
/// once, ahead of the Mac).
public struct NoteLog: Codable, Equatable, Sendable {
    /// Read notes go this long after their last update.
    public static let keepRead: TimeInterval = 7 * 24 * 3600
    public static let cap = 100
    /// A waiting note's text when Claude didn't say what it asks.
    public static let waitingBody = "Waiting on you"

    /// Newest first.
    public private(set) var notes: [LosttyNote]
    /// The sessions waiting at the last `sync`: a waiting episode starts
    /// when a session joins it. Kept with the notes, so a restart doesn't
    /// start them all again.
    public private(set) var waiting: Set<String>

    public init(notes: [LosttyNote] = [], waiting: Set<String> = []) {
        self.notes = notes
        self.waiting = waiting
        sort()
    }

    public var unreadCount: Int { notes.filter { !$0.read }.count }

    public func unreadCount(showing kinds: Set<LosttyNote.Kind>) -> Int {
        notes.filter { !$0.read && kinds.contains($0.kind) }.count
    }

    /// Waiting notes from a session listing: one per terminal. A terminal
    /// that starts waiting, or asks something new, adds its note or revives
    /// it (unread, now); one that stops waiting (answered, or ended) reads
    /// it. True when anything changed.
    @discardableResult
    public mutating func sync(sessions: [RemoteSession], now: Date, newID: () -> UUID = UUID.init) -> Bool {
        let before = self
        let waitingNow = sessions.filter { $0.claude == .waiting }
        for session in waitingNow {
            let row = SessionLabel.row(for: session, now: now)
            let title = row.title
            // The row's line ("Allow? Run the tests"), when Claude says what it asks.
            let question = session.action?.isEmpty == false ? row.action : nil
            let body = question ?? Self.waitingBody
            let started = !waiting.contains(session.id)
            if let i = notes.firstIndex(where: { $0.kind == .waiting && $0.sessionID == session.id }) {
                notes[i].title = title
                notes[i].skin = session.skin?.encoded
                // Mid-episode, only a new question counts: the Mac clears the
                // question and the waiting state apart, so one can go first.
                if started || (question != nil && notes[i].body != body) {
                    notes[i].body = body
                    notes[i].updated = now
                    notes[i].read = false
                }
            } else if started {
                // Deleted while still waiting: back only with the next episode.
                notes.append(LosttyNote(
                    id: newID(), kind: .waiting, created: now, updated: now, title: title, body: body,
                    sessionID: session.id, skin: session.skin?.encoded))
            }
        }
        let ids = Set(waitingNow.map(\.id))
        for i in notes.indices where notes[i].kind == .waiting {
            if let id = notes[i].sessionID, waiting.contains(id), !ids.contains(id) { notes[i].read = true }
        }
        waiting = ids
        sort()
        return self != before
    }

    /// A drop file's change (`NoteDrop`). `.phone` is the keeper's, not the
    /// log's. True when anything changed.
    @discardableResult
    public mutating func apply(_ drop: NoteDrop, now: Date, newID: () -> UUID = UUID.init) -> Bool {
        let before = self
        switch drop {
        case .read(let ids):
            for i in notes.indices where ids.contains(notes[i].id) { notes[i].read = true }
        case .readAll:
            for i in notes.indices { notes[i].read = true }
        case .delete(let ids):
            notes.removeAll { ids.contains($0.id) }
        case .installed(let bundleID, let build):
            for i in notes.indices {
                guard let shipped = notes[i].build, shipped.bundleID == bundleID,
                      Self.isAtMost(shipped.build, build) else { continue }
                notes[i].read = true
            }
        case .build(let info, let sessionID, let terminal, let skin):
            let from = terminal.map(SessionLabel.cleanTitle).flatMap { $0.isEmpty ? nil : $0 } ?? info.project
            let body = ["Build \(info.build)", info.branch, from].filter { !$0.isEmpty }.joined(separator: " · ")
            notes.append(LosttyNote(
                id: newID(), kind: .build, created: now, updated: now, title: "\(info.app) is ready to install",
                body: body, sessionID: sessionID, skin: skin, build: info))
        case .phone:
            break
        }
        sort()
        return self != before
    }

    /// Read notes a week past their last update go; past `cap`, the oldest
    /// read ones go first.
    public mutating func prune(now: Date) {
        notes.removeAll { $0.read && now.timeIntervalSince($0.updated) > Self.keepRead }
        while notes.count > Self.cap {
            if let i = notes.lastIndex(where: \.read) {
                notes.remove(at: i)
            } else {
                notes.removeLast()
            }
        }
    }

    public func json() throws -> Data { try Self.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> NoteLog { try decoder.decode(NoteLog.self, from: data) }

    /// Builds are numbered by time ("202610131331"); anything else matches
    /// only itself.
    static func isAtMost(_ shipped: String, _ installed: String) -> Bool {
        if let a = Int(shipped), let b = Int(installed) { return a <= b }
        return shipped == installed
    }

    private mutating func sort() {
        notes.sort { a, b in
            if a.updated != b.updated { return a.updated > b.updated }
            if a.created != b.created { return a.created > b.created }
            return a.id.uuidString > b.id.uuidString
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// One change for the Mac's keeper, left as a file in
/// `notifications/inbox/` by the phone or a ship script.
public enum NoteDrop: Equatable, Sendable {
    case read([UUID])
    case readAll
    case delete([UUID])
    /// A phone runs this build of `bundleID`: that app's build notes up to it are read.
    case installed(bundleID: String, build: String)
    /// A build published for install; `terminal` is the shipping pane's title.
    case build(NoteBuild, sessionID: String?, terminal: String?, skin: String?)
    case phone(PhoneNoteSettings)

    public init(json data: Data) throws {
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        switch wire.type {
        case "read": self = .read(try wire.need(\.ids))
        case "readAll": self = .readAll
        case "delete": self = .delete(try wire.need(\.ids))
        case "installed": self = .installed(bundleID: try wire.need(\.bundleID), build: try wire.need(\.build))
        case "build":
            self = .build(
                NoteBuild(
                    app: try wire.need(\.app), bundleID: try wire.need(\.bundleID), build: try wire.need(\.build),
                    commit: wire.commit ?? "", branch: wire.branch ?? "", project: wire.project ?? "",
                    installURL: try wire.need(\.installURL)),
                sessionID: wire.sessionID, terminal: wire.terminal, skin: wire.skin)
        case "phone": self = .phone(try wire.need(\.phone))
        default: throw DropError.unknownType(wire.type)
        }
    }

    public func json() throws -> Data {
        var wire = Wire(type: type)
        switch self {
        case .read(let ids), .delete(let ids): wire.ids = ids
        case .readAll: break
        case .installed(let bundleID, let build):
            wire.bundleID = bundleID
            wire.build = build
        case .build(let info, let sessionID, let terminal, let skin):
            wire.app = info.app
            wire.bundleID = info.bundleID
            wire.build = info.build
            wire.commit = info.commit
            wire.branch = info.branch
            wire.project = info.project
            wire.installURL = info.installURL
            wire.sessionID = sessionID
            wire.terminal = terminal
            wire.skin = skin
        case .phone(let phone): wire.phone = phone
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    /// "<type>-<id>.json". Written as "." + this, then renamed: a name
    /// starting with "." is still being written.
    public func fileName(id: UUID) -> String { "\(type)-\(id.uuidString).json" }

    private var type: String {
        switch self {
        case .read: "read"
        case .readAll: "readAll"
        case .delete: "delete"
        case .installed: "installed"
        case .build: "build"
        case .phone: "phone"
        }
    }

    enum DropError: Error, Equatable {
        case unknownType(String)
        case missing(String)
    }

    /// Flat, with a "type", so the ship scripts can write it by hand.
    private struct Wire: Codable {
        var type: String
        var ids: [UUID]?
        var bundleID: String?
        var build: String?
        var app: String?
        var commit: String?
        var branch: String?
        var project: String?
        var installURL: String?
        var sessionID: String?
        var terminal: String?
        var skin: String?
        var phone: PhoneNoteSettings?

        func need<T>(_ field: KeyPath<Wire, T?>) throws -> T {
            guard let value = self[keyPath: field] else { throw DropError.missing("\(field)") }
            return value
        }
    }
}

/// Where a kind of note goes: nowhere, the app's inbox (🔔), or the inbox
/// and a push.
public enum NoteDelivery: String, Codable, CaseIterable, Sendable {
    case off
    case wave
    case push
}

/// One phone's choices, per kind.
public struct NoteSettings: Codable, Equatable, Sendable {
    public var waiting: NoteDelivery
    public var build: NoteDelivery

    public init(waiting: NoteDelivery = .wave, build: NoteDelivery = .wave) {
        self.waiting = waiting
        self.build = build
    }

    public subscript(kind: LosttyNote.Kind) -> NoteDelivery {
        get {
            switch kind {
            case .waiting: waiting
            case .build: build
            }
        }
        set {
            switch kind {
            case .waiting: waiting = newValue
            case .build: build = newValue
            }
        }
    }

    /// The kinds this phone shows.
    public var shown: Set<LosttyNote.Kind> { Set(LosttyNote.Kind.allCases.filter { self[$0] != .off }) }
}

/// A phone's settings as the Mac keeps them (`phones.json`), for pushes.
public struct PhoneNoteSettings: Codable, Equatable, Sendable {
    public var phoneID: String
    /// "iPhone 13", for the Mac's Phone Access window later.
    public var name: String
    public var settings: NoteSettings

    public init(phoneID: String, name: String, settings: NoteSettings) {
        self.phoneID = phoneID
        self.name = name
        self.settings = settings
    }
}

/// The phone's own changes to the notes, laid over each listing until the
/// Mac has had time to apply them: a listing that read `notes.json` just
/// before the Mac did must not bring a swiped-away note back. A change that
/// never reached the Mac is dropped, and the next listing shows the truth.
public struct PendingDrops: Sendable {
    /// After a change reaches the Mac, how long it still lays over listings.
    public static let settle: TimeInterval = 5

    private struct Item: Sendable {
        let id: UUID
        let drop: NoteDrop
        var sent: Date?
    }

    private var items: [Item] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    /// Laid over listings from now on; returns its id for `sent`/`failed`.
    public mutating func add(_ drop: NoteDrop) -> UUID {
        let id = UUID()
        items.append(Item(id: id, drop: drop))
        return id
    }

    public mutating func sent(_ id: UUID, at date: Date) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].sent = date }
    }

    public mutating func failed(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// `fetched` with the changes still pending applied on top.
    public mutating func overlay(_ fetched: NoteLog, now: Date) -> NoteLog {
        items.removeAll { $0.sent.map { now.timeIntervalSince($0) > Self.settle } ?? false }
        var log = fetched
        for item in items { log.apply(item.drop, now: now) }
        return log
    }
}
