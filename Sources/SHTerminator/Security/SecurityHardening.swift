import AppKit
import Carbon
import Darwin

/// Every OS-level protection this app applies lives here, in one place, so
/// the security posture can be read and audited without hunting through the
/// rest of the codebase. See SECURITY.md for the full threat model and the
/// residual risks this cannot close. (The window lock lives next door, in
/// `PrivacyLock.swift`; the paste check in `PastePolicy.swift`.)
@MainActor
enum SecurityHardening {
    /// Call once, as early as possible during process startup.
    static func hardenProcess() {
        // Never let a crash write a core dump: panes may hold passwords,
        // keys or seed phrases in memory, and a core file would persist
        // that to disk.
        var limit = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &limit)
    }

    /// Call right after creating a window, and again whenever it becomes key
    /// or enters/exits full screen (those transitions can recreate the
    /// window's surface and silently reset `sharingType`).
    static func harden(window: NSWindow) {
        // Excludes the window from screenshots, screen recording and
        // screen-sharing (Cmd+Shift+4/5, ScreenCaptureKit, QuickTime,
        // Zoom/Meet/Slack screen share all skip a window with sharingType .none).
        window.sharingType = .none

        // Never let macOS serialize this window's content (which may include
        // on-screen secrets) into ~/Library/Saved Application State/.
        window.isRestorable = false
    }

    // MARK: - Secure keyboard entry

    private static var secureInputEngaged = false

    /// Turns macOS "secure event input" on while this app is frontmost (and
    /// the setting is on), off otherwise. While it's on, other processes'
    /// keyboard event taps — the usual way keyloggers and some "productivity"
    /// tools read keystrokes — get nothing from what is typed here, e.g. a
    /// `sudo` or `ssh` password. Same mechanism as Terminal.app's
    /// "Secure Keyboard Entry". Call on app activation/deactivation and when
    /// the setting changes; calls to the OS stay balanced.
    static func updateSecureKeyboardEntry() {
        let wanted = AppSettings.secureKeyboardEntry && NSApp.isActive
        guard wanted != secureInputEngaged else { return }
        if wanted {
            EnableSecureEventInput()
        } else {
            DisableSecureEventInput()
        }
        secureInputEngaged = wanted
    }

    // MARK: - Clipboard

    /// Markers from nspasteboard.org that clipboard managers (Maccy, Paste,
    /// Raycast, Alfred, 1Password…) honour by not recording the entry in
    /// their history.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Puts `string` on the clipboard marked as a secret: clipboard managers
    /// skip it, and it stays on this Mac (no Universal Clipboard hand-off to
    /// other devices). With `clearAfter`, the clipboard is emptied after that
    /// many seconds — unless something else was copied in the meantime (in
    /// any app), which is then left alone.
    static func copySecret(_ string: String, clearAfter seconds: TimeInterval? = nil) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(string, forType: .string)
        pasteboard.setString("", forType: concealedType)
        pasteboard.setString("", forType: transientType)

        guard let seconds else { return }
        let ownChange = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard pasteboard.changeCount == ownChange else { return }
            pasteboard.clearContents()
        }
    }

    // MARK: - Text editing

    /// Text typed or pasted here — commands, hosts, keys, passwords — must
    /// stay exactly as entered: no spelling or grammar checks, no "smart"
    /// quotes, dashes or replacements (`"` → `“`, `--` → `—` break a
    /// command silently), and no Writing Tools (Apple Intelligence), which
    /// would offer to send the text off for rewriting. For the notes' text
    /// view and, through `PlainTextField`/`PlainSearchField`, the field
    /// editor of every editable field.
    static func disableTextRewriting(in textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .none
        }
    }

    // MARK: - Private files

    /// Atomically replaces `url` with `data`, created owner-only (0600) from
    /// the first byte, in a directory that is (made) 0700. Unlike
    /// `Data.write(options: .atomic)` followed by `chmod`, there's no moment
    /// where the file exists with the default, group/world-readable mode.
    static func writePrivateFile(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The mode above only applies to a directory created just now; an
        // existing one (older build, made by hand) is tightened here.
        guard chmod(dir.path, 0o700) == 0 else { throw posixError() }

        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }

        var failure: Error? = data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let n = write(fd, buffer.baseAddress! + written, buffer.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    return posixError()
                }
                written += n
            }
            return nil
        }
        if failure == nil, fsync(fd) != 0 { failure = posixError() }
        close(fd)
        if failure == nil, rename(temp.path, url.path) != 0 { failure = posixError() }
        if let failure {
            unlink(temp.path)
            throw failure
        }
    }

    private static func posixError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
