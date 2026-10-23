import Foundation

/// The free-form scratch notes shown under the favorites sidebar. One text
/// shared by every window, kept across restarts in
/// `~/Library/Application Support/SHTerminator/notes.txt` (dir 0700,
/// file 0600) — plain text, see SECURITY.md. With
/// `AppSettings.persistNotes` off, the text lives in memory only and the
/// file is deleted.
@MainActor
final class NotesStore {
    static let shared = NotesStore()
    /// Posted after `text` changes; `object` is whoever made the change, so
    /// that editor can skip refreshing itself.
    static let didChange = Notification.Name("NotesStoreDidChange")

    private(set) var text = ""
    private var saveScheduled = false

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SHTerminator", isDirectory: true)
            .appendingPathComponent("notes.txt")
    }()

    private init() {
        if AppSettings.persistNotes {
            text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Call after `AppSettings.persistNotes` changes: turning it off deletes
    /// the file now, turning it on writes the current text.
    func persistenceSettingChanged() {
        saveScheduled = true
        flush()
    }

    func setText(_ newText: String, from source: AnyObject?) {
        guard newText != text else { return }
        text = newText
        NotificationCenter.default.post(name: NotesStore.didChange, object: source)
        scheduleSave()
    }

    /// Typing saves at most about once a second instead of on every keystroke.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.flush()
        }
    }

    /// Writes pending changes now — also called on app quit.
    func flush() {
        guard saveScheduled else { return }
        saveScheduled = false
        do {
            if text.isEmpty || !AppSettings.persistNotes {
                // Cleared (or memory-only) notes leave nothing behind on disk.
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                try SecurityHardening.writePrivateFile(Data(text.utf8), to: fileURL)
            }
        } catch {
            NSLog("sh_terminator: failed to save notes: \(error.localizedDescription)")
        }
    }
}
