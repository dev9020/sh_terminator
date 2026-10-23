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
/// `PastePolicy`), a tap on everything the user sends, and a filter on what
/// the program in the pane may ask of the terminal (see `HostRequestFilter`).
final class TerminalPaneView: LocalProcessTerminalView {
    var onUserInput: ((UserInput) -> Void)?

    private lazy var hostRequestFilter = HostRequestFilter(view: self)

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
    /// — the text is wrapped in bracketed-paste markers when the program
    /// asked for them, otherwise its lines are joined with spaces. Broadcast
    /// repeats the same call in the other panes, so each one gets this
    /// treatment for its own program, whatever the source pane's mode was.
    func sendPaste(_ text: String, runsLines: Bool = false) {
        let clean = PastePolicy.strippingControlCharacters(text)
        let bracketed = getTerminal().bracketedPasteMode
        let typed = PastePolicy.typedText(clean, bracketedPaste: bracketed, runsLines: runsLines)
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
        onUserInput?(.paste(clean, runsLines: runsLines))
    }

    // MARK: - Guarded paste

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        pasteAfterCheck(text)
    }

    private func pasteAfterCheck(_ text: String) {
        switch PastePolicy.concern(for: text, bracketedPaste: getTerminal().bracketedPasteMode) {
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
            confirm(
                message: count == 1 ? "This paste ends a line" : "This paste contains \(count) line breaks",
                info: "The program in this pane doesn't use bracketed paste, so every line break acts as Return and runs the line before it right away.",
                buttons: ["Paste as One Line", "Paste and Run Lines", "Cancel"]
            ) { choice in
                switch choice {
                case 0:
                    self.sendPaste(PastePolicy.joiningLines(text))
                case 1:
                    self.sendPaste(text, runsLines: true)
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
