import Foundation

/// The free-form scratch notes shown under the favorites sidebar. One text
/// shared by every window, kept across restarts in
/// `~/Library/Application Support/SHTerminator/notes.txt` (dir 0700,
/// file 0600) — plain text, see SECURITY.md.
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
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
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
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if text.isEmpty {
                // Cleared notes leave nothing behind on disk.
                try? fm.removeItem(at: fileURL)
            } else {
                try Data(text.utf8).write(to: fileURL, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
        } catch {
            NSLog("sh_terminator: failed to save notes: \(error.localizedDescription)")
        }
    }
}
