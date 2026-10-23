import AppKit
import SwiftTerm

/// Which links a ⌘-click in a pane may open. The program in the pane decides
/// both what a link says and where it goes (OSC 8), so only schemes that
/// open in a browser or mail client are allowed — never a file, an app or a
/// custom URL handler (`file:///…/x.command` would run a script).
enum LinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func url(for link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else { return nil }
        return url
    }
}

/// Stands between SwiftTerm's view and `LocalProcessTerminalView`'s own
/// handling of what the program in the pane asks the terminal to do. Any
/// program can ask — including one on a remote host behind `ssh`, or a file
/// someone `cat`s — so:
/// - **Clipboard (OSC 52)**: reading is refused (the program would get
///   whatever is on the clipboard, e.g. a password just copied), and so is
///   writing (it could swap in a command for the user to paste elsewhere).
/// - **Links**: opened only per `LinkPolicy`, and only after the user saw
///   where they really go.
/// Everything else is passed on unchanged.
///
/// `LocalProcessTerminalView` implements these as non-`open` methods, so
/// they can't be overridden in a subclass; replacing its `terminalDelegate`
/// with this object is the documented way to customise them.
@MainActor
final class HostRequestFilter: @preconcurrency TerminalViewDelegate {
    private unowned let view: LocalProcessTerminalView

    init(view: LocalProcessTerminalView) {
        self.view = view
    }

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func clipboardCopy(source: TerminalView, content: Data) {}

    /// Longest destination shown in the confirmation, in characters.
    nonisolated static let maxShownLinkLength = 1000

    /// With OSC 8 the program picks the text shown for a link and, apart
    /// from it, where it goes — so the real destination is shown, in a sheet
    /// on this pane's window, before anything is opened.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = LinkPolicy.url(for: link), let window = view.window else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open this link?"
        alert.informativeText = Self.shownDestination(url)
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.sharingType = .none
        alert.beginSheetModal(for: window) { response in
            // Locking cancels the sheet (see PaneWindowController.privacyLockDidChange).
            guard response == .alertFirstButtonReturn, !PrivacyLock.shared.isEngaged else { return }
            NSWorkspace.shared.open(url)
        }
    }

    /// `url` as text, cut to `maxShownLinkLength`. `absoluteString` is
    /// percent-encoded, so no character in it can hide or reorder the rest.
    nonisolated static func shownDestination(_ url: URL) -> String {
        let text = url.absoluteString
        return text.count > maxShownLinkLength ? text.prefix(maxShownLinkLength) + "…" : text
    }

    // MARK: - Passed through

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        view.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        view.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        view.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        view.scrolled(source: source, position: position)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        view.rangeChanged(source: source, startY: startY, endY: endY)
    }

    func bell(source: TerminalView) {
        view.bell(source: source)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        view.iTermContent(source: source, content: content)
    }
}
