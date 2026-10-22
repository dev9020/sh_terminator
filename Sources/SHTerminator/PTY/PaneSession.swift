import AppKit
import SwiftTerm

/// One terminal pane = one independent shell process on its own pty.
/// Panes never share state with each other beyond normal OS process isolation.
@MainActor
final class PaneSession: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminalView: LocalProcessTerminalView

    /// Called when the pane's shell process exits (user typed `exit`, or it crashed).
    var onProcessExit: (() -> Void)?

    override init() {
        terminalView = LocalProcessTerminalView(frame: .zero)
        super.init()
        terminalView.processDelegate = self
        startShell()
    }

    private func startShell() {
        let shell = PaneSession.loginShellPath()
        let execName = "-" + (shell as NSString).lastPathComponent
        // environment: nil lets SwiftTerm pick its own minimal default set
        // (TERM/COLORTERM/LANG/USER/HOME/...); we never inject our own
        // app-specific variables into the user's shell environment.
        terminalView.startProcess(
            executable: shell,
            execName: execName,
            currentDirectory: NSHomeDirectory()
        )
    }

    func terminate() {
        terminalView.terminate()
    }

    /// Reads the user's login shell from the directory service (same source
    /// macOS's own Terminal.app uses), rather than trusting the `SHELL`
    /// environment variable, which could be altered before launch.
    private static func loginShellPath() -> String {
        let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
        guard bufsize != -1 else { return "/bin/zsh" }
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
        defer { buffer.deallocate() }
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) == 0, result != nil, let shell = pwd.pw_shell else {
            return "/bin/zsh"
        }
        return String(cString: shell)
    }

    // MARK: - LocalProcessTerminalViewDelegate
    //
    // SwiftTerm can invoke these from its own background I/O thread, so they
    // are deliberately `nonisolated` and hop to the main actor themselves
    // before touching any pane/window state.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.onProcessExit?()
        }
    }
}
