import AppKit
import SwiftTerm

/// What the user sent into a pane, as seen by `onUserInput` — for
/// broadcasting it to the other panes of the window.
enum UserInput {
    /// Typed keys, already encoded for the program in the pane.
    case bytes(ArraySlice<UInt8>)
    /// Pasted text, with control characters already dropped but before
    /// bracketed-paste wrapping or line joining — each receiving pane applies
    /// those for its own program (see `TerminalPaneView.sendPaste`).
    case paste(String, runsLines: Bool)
}

/// SwiftTerm's view plus what this app needs around it: a guarded ⌘V (see
/// `PastePolicy`), a tap on everything the user sends, and filters on what
/// the program in the pane may ask of the terminal (see `HostRequestFilter`
/// and `HostOutputFilter`).
final class TerminalPaneView: LocalProcessTerminalView {
    var onUserInput: ((UserInput) -> Void)?

    /// How many other panes broadcast would pass this pane's input on to
    /// right now (0 when broadcast is off) — so the paste check can say so.
    var broadcastPeerCount: (() -> Int)?

    private lazy var hostRequestFilter = HostRequestFilter(view: self)
    private var hostOutputFilter = HostOutputFilter()

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminalDelegate = hostRequestFilter
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Set while the terminal emulator itself answers the program (cursor
    /// position reports, device attributes, …) — those replies go through
    /// the same path as user input but must never be broadcast.
    private var sendingTerminalReply = false
    private var sendingPaste = false

    private static let bracketedPasteStart: [UInt8] = Array("\u{1b}[200~".utf8)
    private static let bracketedPasteEnd: [UInt8] = Array("\u{1b}[201~".utf8)

    // MARK: - Process

    /// Starts the pane's program. SwiftTerm opens the pty with `forkpty`,
    /// which leaves this end of it inheritable: without close-on-exec,
    /// every program started afterwards — the shells of panes opened later
    /// and everything they run — would hold it, and could read what this
    /// pane shows and type into it.
    func startIsolatedProcess(executable: String, args: [String] = [], environment: [String]? = nil, execName: String? = nil, currentDirectory: String? = nil) {
        startProcess(executable: executable, args: args, environment: environment, execName: execName, currentDirectory: currentDirectory)
        let fd = process.childfd
        if fd >= 0 {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
    }

    // MARK: - Output

    /// Everything the program writes passes `HostOutputFilter` before
    /// SwiftTerm interprets it.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: hostOutputFilter.filter(slice)[...])
    }

    /// Escape sequences the app itself draws with. They go through the same
    /// filter, so it stays in step with SwiftTerm's parser (a sequence the
    /// program left open would otherwise be ended here, unchecked).
    func feedLocally(_ text: String) {
        dataReceived(slice: Array(text.utf8)[...])
    }

    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        sendingTerminalReply = true
        defer { sendingTerminalReply = false }
        super.send(source: source, data: data)
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        if !sendingTerminalReply && !sendingPaste {
            onUserInput?(.bytes(data))
        }
    }

    /// Types `text` as a paste, made safe for the program in this pane:
    /// control characters are always dropped (an ESC could end a bracketed
    /// paste early), and line breaks never act as Return unless `runsLines`
    /// — they are kept only when `pasteIsBracketedByShell`, otherwise the
    /// lines are joined with spaces. The text is wrapped in bracketed-paste
    /// markers whenever the program asked for them. Broadcast
    /// repeats the same call in the other panes, so each one gets this
    /// treatment for its own program, whatever the source pane's mode was.
    /// `relaysRunsLines` is what the other panes get for `runsLines`
    /// (by default the same): "Paste As Is" keeps the lines for a program
    /// that says it won't run them, which says nothing about theirs.
    func sendPaste(_ text: String, runsLines: Bool = false, relaysRunsLines: Bool? = nil) {
        let clean = PastePolicy.strippingControlCharacters(text)
        let bracketed = getTerminal().bracketedPasteMode
        let typed = PastePolicy.typedText(clean, bracketedPaste: pasteIsBracketedByShell, runsLines: runsLines)
        guard !typed.isEmpty else { return }
        sendingPaste = true
        if bracketed {
            send(data: Self.bracketedPasteStart[...])
            send(txt: typed)
            send(data: Self.bracketedPasteEnd[...])
        } else {
            send(txt: typed)
        }
        sendingPaste = false
        onUserInput?(.paste(clean, runsLines: relaysRunsLines ?? runsLines))
    }

    /// Shells that switch bracketed paste on themselves at every prompt
    /// and take a pasted line break as text.
    private static let bracketedPasteShells: Set<String> = ["zsh", "fish"]

    /// Whether line breaks in a bracketed paste will really stay text: the
    /// program asked for bracketed paste *and* it is the pane's own shell,
    /// zsh or fish, at its prompt. The mode is only a flag that any program
    /// — or any output, such as a `cat`-ed file or a remote host's login
    /// banner — can switch on; a program that does without honouring it
    /// (`sh`, macOS's bash 3.2, many REPLs) would run every pasted line.
    /// "At its prompt" is the line editor's terminal mode, not just the
    /// shell being in the foreground: while the shell itself runs `read`,
    /// `vared` or `select`, the first line goes to that builtin and the
    /// rest is then read by the line editor as typed keys — and run.
    var pasteIsBracketedByShell: Bool {
        guard getTerminal().bracketedPasteMode, inputMode == .shellLineEditor, let name = PaneSession.processName(process.shellPid) else { return false }
        return Self.bracketedPasteShells.contains(name)
    }

    // MARK: - Input mode

    /// What the pane's terminal does with input right now, as far as
    /// pasting and broadcast care.
    enum InputMode: Equatable {
        /// The pane's own shell at its prompt: its line editor (ZLE,
        /// readline, fish) turns the terminal's echo *off* and echoes
        /// keys itself, so whatever is typed shows up — and Return runs it.
        case shellLineEditor
        /// A line read without echo — a `sudo`/`ssh`/`gpg` password prompt
        /// (`readpassphrase`, `getpass`, `read -s`): canonical mode, echo off.
        case hiddenLine
        /// Anything else: an echoing program, a full-screen one (vim, less),
        /// `ssh` with the remote side echoing, no process at all.
        case other
    }

    /// A password prompt keeps the terminal canonical with echo off; a
    /// line editor and full-screen programs take it out of canonical mode.
    nonisolated static func inputMode(localFlags: tcflag_t, foregroundIsShell: Bool) -> InputMode {
        let echo = localFlags & tcflag_t(ECHO) != 0
        let canonical = localFlags & tcflag_t(ICANON) != 0
        if !echo && canonical { return .hiddenLine }
        if !echo && !canonical && foregroundIsShell { return .shellLineEditor }
        return .other
    }

    var inputMode: InputMode {
        guard let process, process.running, process.childfd >= 0 else { return .other }
        var attributes = termios()
        guard tcgetattr(process.childfd, &attributes) == 0 else { return .other }
        let group = tcgetpgrp(process.childfd)
        return Self.inputMode(localFlags: attributes.c_lflag, foregroundIsShell: group > 0 && group == process.shellPid)
    }

    // MARK: - Guarded paste

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        pasteAfterCheck(text)
    }

    private func pasteAfterCheck(_ text: String) {
        switch PastePolicy.concern(for: text, bracketedPaste: pasteIsBracketedByShell) {
        case nil:
            sendPaste(text)

        case .controlCharacters(let count):
            confirm(
                message: count == 1 ? "The clipboard contains a control character" : "The clipboard contains \(count) control characters",
                info: "Hidden control characters (such as Escape) can make the program in this pane act as if you had typed something else — including running a command. Text copied from web pages can carry them on purpose.",
                buttons: ["Paste Without Them", "Cancel"]
            ) { choice in
                if choice == 0 { self.pasteAfterCheck(PastePolicy.strippingControlCharacters(text)) }
            }

        case .runsLines(let count):
            let claimsBracketedPaste = getTerminal().bracketedPasteMode
            var info = claimsBracketedPaste
                ? "The program in this pane says it takes bracketed paste, but it isn't your zsh or fish prompt, so that can't be relied on: if the program doesn't, every line break acts as Return and runs the line before it right away."
                : "The program in this pane doesn't use bracketed paste, so every line break acts as Return and runs the line before it right away."
            let peers = broadcastPeerCount?() ?? 0
            if peers > 0 {
                let others = peers == 1 ? "the other pane" : "up to \(peers) other panes"
                info += claimsBracketedPaste
                    ? " Broadcast is on: in \(others) the lines are joined unless that pane's own zsh or fish prompt takes them."
                    : " Broadcast is on: Paste and Run Lines runs the lines in \(others) too."
            }
            confirm(
                message: count == 1 ? "This paste ends a line" : "This paste contains \(count) line breaks",
                info: info,
                buttons: ["Paste as One Line", claimsBracketedPaste ? "Paste As Is" : "Paste and Run Lines", "Cancel"]
            ) { choice in
                switch choice {
                case 0:
                    self.sendPaste(PastePolicy.joiningLines(text))
                case 1:
                    if claimsBracketedPaste && !self.getTerminal().bracketedPasteMode {
                        // The program turned bracketed paste off while the
                        // question was up: "As Is" would now run every line.
                        // Ask again, for what the pane does now.
                        self.pasteAfterCheck(text)
                        return
                    }
                    // "As Is" vouches only for this pane's program.
                    self.sendPaste(text, runsLines: true, relaysRunsLines: claimsBracketedPaste ? false : nil)
                default:
                    break
                }
            }
        }
    }

    /// Asks as a sheet on this pane's window; `completion` gets the index of
    /// the button clicked. The first button is the default (Return), the
    /// last one is Cancel (Escape). The clipboard text itself is never shown:
    /// it may be a secret, and the alert is a separate window. If the windows
    /// got locked meanwhile, nothing is pasted (locking also cancels the
    /// sheet, see `PaneWindowController.privacyLockDidChange`).
    private func confirm(message: String, info: String, buttons: [String], completion: @escaping (Int) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        for title in buttons { alert.addButton(withTitle: title) }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.sharingType = .none
        alert.beginSheetModal(for: window) { response in
            guard !PrivacyLock.shared.isEngaged else { return }
            completion(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            window.makeFirstResponder(self)
        }
    }
}
