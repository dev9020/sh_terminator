import AppKit
import Darwin
import SwiftTerm

/// One terminal pane = one independent shell process on its own pty.
/// Panes never share state with each other beyond normal OS process isolation.
@MainActor
final class PaneSession: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminalView: TerminalPaneView

    /// Called when the pane's shell process exits (user typed `exit`, or it crashed).
    var onProcessExit: (() -> Void)?

    /// Called when the program in the pane sets the title (OSC 0/2).
    var onTitleChange: (() -> Void)?

    /// The title the program in the pane set last, if any.
    private(set) var programTitle: String?

    /// `currentDirectory` is where the new shell starts — normally the
    /// directory of the pane being split; the home directory if nil.
    init(currentDirectory: String? = nil) {
        terminalView = TerminalPaneView(frame: .zero)
        super.init()
        terminalView.processDelegate = self
        applyFontSize()
        startShell(in: currentDirectory ?? NSHomeDirectory())
    }

    private func startShell(in directory: String) {
        let shell = PaneSession.loginShellPath()
        let execName = "-" + (shell as NSString).lastPathComponent
        // environment: nil lets SwiftTerm pick its own minimal default set
        // (TERM/COLORTERM/LANG/USER/HOME/...); we never inject our own
        // app-specific variables into the user's shell environment.
        terminalView.startProcess(
            executable: shell,
            execName: execName,
            currentDirectory: directory
        )
    }

    /// Types `text` at the shell prompt without running it: trailing line
    /// breaks are dropped, and the text goes in as a bracketed paste when the
    /// shell supports it (zsh/bash/fish do), so even an embedded newline
    /// can't submit the line. If the program in the pane hasn't enabled
    /// bracketed paste, inner line breaks are turned into spaces instead.
    func insertWithoutRunning(_ text: String) {
        var text = text
        while let last = text.last, last.isNewline || last.isWhitespace { text.removeLast() }
        guard !text.isEmpty else { return }

        if !terminalView.getTerminal().bracketedPasteMode {
            text = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
        }
        terminalView.sendPaste(text)
    }

    func terminate() {
        terminalView.terminate()
    }

    // MARK: - Scrollback

    /// Wipes the scrollback and every screen line above the cursor, keeping
    /// only the line the cursor is on (normally the prompt) at the top — like
    /// ⌘K in Terminal.app. In a full-screen program (vim, less, top…) the
    /// screen is the program's own and is left alone; the shell's scrollback
    /// underneath is still wiped.
    ///
    /// SwiftTerm drops the lines from its buffer; the memory they used is
    /// released for reuse, not zeroed, so this is hygiene against shoulder
    /// surfing and accidental copy, not a guarantee against a memory dump.
    func clearScrollback() {
        let terminal = terminalView.getTerminal()
        terminalView.selectNone()
        if !terminal.isCurrentBufferAlternate {
            let cursor = terminal.getCursorLocation()
            if cursor.y > 0 {
                // Cursor home, delete the lines above the cursor line (which
                // moves it up to row 1), put the cursor back in its column.
                terminalView.feed(text: "\u{1b}[H\u{1b}[\(cursor.y)M\u{1b}[1;\(cursor.x + 1)H")
            }
        }
        terminal.clearScrollback()
    }

    // MARK: - Font

    /// Applies `AppSettings.fontSize` (0 = SwiftTerm's default size).
    func applyFontSize() {
        let size = AppSettings.fontSize > 0 ? AppSettings.fontSize : NSFont.systemFontSize
        guard terminalView.font.pointSize != size else { return }
        terminalView.font = NSFont(descriptor: terminalView.font.fontDescriptor, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Process info

    /// The shell's current directory, read from the kernel (works whatever
    /// the shell is and needs no shell integration).
    var currentDirectory: String? {
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    /// Name of the program in the foreground of this pane (e.g. `ssh`,
    /// `vim`), or nil while the shell itself is at its prompt.
    var foregroundProgramName: String? {
        let process = terminalView.process!
        guard process.running, process.childfd >= 0 else { return nil }
        let group = tcgetpgrp(process.childfd)
        guard group > 0, group != process.shellPid else { return nil }
        return Self.processName(group) ?? "a program"
    }

    /// Program name for the pane's header: the foreground program, or the
    /// shell's own name at the prompt.
    var displayProgramName: String {
        foregroundProgramName ?? Self.processName(terminalView.process.shellPid) ?? "shell"
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard pid > 0, proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
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

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            self.programTitle = title.isEmpty ? nil : title
            self.onTitleChange?()
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.onProcessExit?()
        }
    }
}
