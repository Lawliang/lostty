#if os(iOS)
import Foundation
import LosttyRemote

/// Lostty Mobile's notifications on the phone: read with each listing;
/// changed here at once, then by a drop file the Mac's Lostty applies for
/// every phone.
extension MobileStore {
    static let noteSettingsKey = "LosttyNoteSettings"
    static let phoneIDKey = "LosttyPhoneID"
    static let reportedBuildKey = "LosttyReportedBuild"

    /// The notes this phone shows: every kind it hasn't turned off.
    var shownNotes: [LosttyNote] { notes.notes.filter { noteSettings.shown.contains($0.kind) } }

    /// For 🔔's badge.
    var unreadNotes: Int { notes.unreadCount(showing: noteSettings.shown) }

    static func loadNoteSettings(from defaults: UserDefaults) -> NoteSettings {
        defaults.data(forKey: noteSettingsKey).flatMap { try? JSONDecoder().decode(NoteSettings.self, from: $0) } ?? NoteSettings()
    }

    /// This phone to the Mac, made the first time it's asked for.
    var phoneID: String {
        if let id = defaults.string(forKey: Self.phoneIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.phoneIDKey)
        return id
    }

    func loadNotes(on connection: RemoteConnection) async {
        // Unreadable, or the read failed: keep the last notes.
        guard let log = try? await connection.notes() else { return }
        notes = pendingNotes.overlay(log, now: Date())
        await reportBuild(on: connection)
    }

    func markNotesRead(_ ids: [UUID]) { send(.read(ids)) }
    /// The notes this phone shows; kinds it turned off stay as they are
    /// for other phones.
    func markAllNotesRead() {
        let unread = shownNotes.filter { !$0.read }.map(\.id)
        if !unread.isEmpty { send(.read(unread)) }
    }
    func deleteNotes(_ ids: [UUID]) { send(.delete(ids)) }

    func setDelivery(_ delivery: NoteDelivery, for kind: LosttyNote.Kind) {
        noteSettings[kind] = delivery
        if let data = try? JSONEncoder().encode(noteSettings) { defaults.set(data, forKey: Self.noteSettingsKey) }
        send(.phone(PhoneNoteSettings(phoneID: phoneID, name: DeviceModel.current, settings: noteSettings)))
    }

    /// Once per build of this app: the Mac reads its build notes up to it.
    private func reportBuild(on connection: RemoteConnection) async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              defaults.string(forKey: Self.reportedBuildKey) != build else { return }
        do {
            try await connection.drop(.installed(bundleID: bundleID, build: build))
            defaults.set(build, forKey: Self.reportedBuildKey)
        } catch {
            // Next listing tries again.
        }
    }

    /// Shown at once, and kept over listings until the Mac has applied it
    /// (`PendingDrops`); every phone follows. One that doesn't reach the Mac
    /// is undone by the next listing.
    private func send(_ drop: NoteDrop) {
        notes.apply(drop, now: Date())
        #if DEBUG
        if isGallery { return }
        #endif
        guard !settings.remoteHosts.isEmpty else { return }
        let id = pendingNotes.add(drop)
        Task {
            do {
                try await withConnection { try await $0.drop(drop) }
                pendingNotes.sent(id, at: Date())
            } catch {
                pendingNotes.failed(id)
            }
        }
    }
}
#endif
