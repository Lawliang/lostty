#if os(macOS)
import Foundation
import LosttyRemote

/// Lostty Mobile: keeps the phone's notifications (🔔). Waiting notes come
/// from the same session listing the phone reads, after every tmux change;
/// everything else arrives as drop files in `inbox/`. After a change it
/// saves `notes.json` and wakes tmux's change channel, so a phone that's
/// watching re-lists and reads the notes. Only one Lostty process keeps
/// them: the one holding the folder's lock. Another takes over when that
/// one quits.
@MainActor
final class NotesKeeper {
    static let shared = NotesKeeper(
        folder: NotesFolder(root: NotesFolder.standard),
        list: { NotesKeeper.listing(TmuxClient().readSessionListing(), serverExists: TmuxClient.serverSocketExists) },
        signal: { _ = TmuxClient().run(TmuxHooks.signalArgs) })

    /// A session listing that failed while the server may still be there is
    /// unknown (nil), not "no sessions": that would read every waiting note
    /// and start them all again on the next good listing.
    nonisolated static func listing(_ listed: [RemoteSession]?, serverExists: Bool) -> [RemoteSession]? {
        listed ?? (serverExists ? nil : [])
    }

    private(set) var log = NoteLog()
    private(set) var isKeeping = false

    private let folder: NotesFolder
    /// The sessions now, nil when unknown; called off the main thread.
    private let list: @Sendable () -> [RemoteSession]?
    /// Wakes tmux's change channel; called off the main thread.
    private let signal: @Sendable () -> Void
    private var phones: [String: PhoneNoteSettings] = [:]
    private var lockFD: Int32?
    private var inboxSource: DispatchSourceFileSystemObject?
    private var observer: NSObjectProtocol?
    /// tmux runs here, off the main thread.
    private let tmux = DispatchQueue(label: "Lostty notes", qos: .utility)

    init(
        folder: NotesFolder, list: @escaping @Sendable () -> [RemoteSession]?, signal: @escaping @Sendable () -> Void
    ) {
        self.folder = folder
        self.list = list
        self.signal = signal
    }

    func start() {
        guard observer == nil else { return }
        do { try folder.create() } catch { return }
        observer = NotificationCenter.default.addObserver(forName: .losttySessionsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionsChanged() }
        }
        sessionsChanged()
    }

    /// Takes over keeping once the lock is free (the other Lostty quit),
    /// then re-syncs with the sessions.
    func sessionsChanged() {
        if !isKeeping {
            guard let fd = folder.lock() else { return }
            lockFD = fd
            isKeeping = true
            log = folder.loadNotes()
            phones = folder.loadPhones()
            watchInbox()
            drainInbox()
        }
        relist()
    }

    /// A listing's waiting notes; nil (unknown) changes nothing.
    func apply(listing sessions: [RemoteSession]?) {
        guard let sessions, log.sync(sessions: sessions, now: Date()) else { return }
        save()
    }

    private func watchInbox() {
        let fd = open(folder.inbox.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drainInbox() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        inboxSource = source
    }

    private func drainInbox() {
        var changed = false
        for drop in folder.drain() {
            if case .phone(let phone) = drop {
                phones[phone.phoneID] = phone
                try? folder.save(phones: phones)
            } else if log.apply(drop, now: Date()) {
                changed = true
            }
        }
        if changed { save() }
    }

    private func relist() {
        let list = list
        tmux.async { [weak self] in
            let sessions = list()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(listing: sessions) }
            }
        }
    }

    private func save() {
        log.prune(now: Date())
        do { try folder.save(log) } catch { return }
        // The phone's watch re-lists, and reads the notes with it. Our own
        // listing that follows finds nothing new, so this doesn't loop.
        let signal = signal
        tmux.async { signal() }
    }
}
#endif
