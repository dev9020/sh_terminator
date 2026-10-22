import AppKit
import Darwin

/// Every OS-level protection this app applies lives here, in one place, so
/// the security posture can be read and audited without hunting through the
/// rest of the codebase. See SECURITY.md for the full threat model and the
/// residual risks this cannot close.
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

    private static var pendingClearToken: UUID?

    /// Copies the current selection in `terminalView` the normal way, then
    /// clears the system clipboard after `seconds` — for pasting a password
    /// or seed phrase without leaving it sitting in clipboard history
    /// indefinitely. Regular Cmd+C still behaves normally everywhere else;
    /// this is an additional opt-in command, not a restriction.
    static func copyAndScheduleClipboardClear(from terminalView: Any, after seconds: TimeInterval = 20) {
        guard let copyable = terminalView as? NSResponder, copyable.responds(to: #selector(NSText.copy(_:))) else { return }
        copyable.perform(#selector(NSText.copy(_:)), with: copyable)

        let token = UUID()
        pendingClearToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            // If another copy happened since, its own timer owns the clear.
            guard pendingClearToken == token else { return }
            NSPasteboard.general.clearContents()
        }
    }
}
