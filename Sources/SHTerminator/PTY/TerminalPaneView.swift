import AppKit
import SwiftTerm

/// What the user sent into a pane, as seen by `onUserInput` — for
/// broadcasting it to the other panes of the window.
enum UserInput {
    /// Typed keys, already encoded for the program in the pane.
    case bytes(ArraySlice<UInt8>)
    /// Pasted text, before bracketed-paste wrapping — each receiving pane
    /// wraps it according to its own program's mode.
    case paste(String)
}

/// SwiftTerm's view plus the two things this app needs at the input side:
/// a guarded ⌘V (see `PastePolicy`) and a tap on everything the user sends.
final class TerminalPaneView: LocalProcessTerminalView {
    var onUserInput: ((UserInput) -> Void)?

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

    /// Types `text` as a paste: wrapped in bracketed-paste markers when the
    /// program in the pane asked for them, as plain keystrokes otherwise.
    /// No checks — callers decide what is safe to send.
    func sendPaste(_ text: String) {
        guard !text.isEmpty else { return }
        sendingPaste = true
        if getTerminal().bracketedPasteMode {
            send(data: Self.bracketedPasteStart[...])
            send(txt: text)
            send(data: Self.bracketedPasteEnd[...])
        } else {
            send(txt: text)
        }
        sendingPaste = false
        onUserInput?(.paste(text))
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
                    let oneLine = text
                        .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
                        .joined(separator: " ")
                    self.sendPaste(oneLine)
                case 1:
                    self.sendPaste(text)
                default:
                    break
                }
            }
        }
    }

    /// Asks as a sheet on this pane's window; `completion` gets the index of
    /// the button clicked. The first button is the default (Return), the
    /// last one is Cancel (Escape). The clipboard text itself is never shown:
    /// it may be a secret, and the alert is a separate window.
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
            completion(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            window.makeFirstResponder(self)
        }
    }
}
