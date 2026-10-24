import AppKit
import Testing
@testable import SHTerminator

@Suite struct InputModeTests {
    private let echo = tcflag_t(ECHO)
    private let canonical = tcflag_t(ICANON)

    @Test func passwordPromptIsCanonicalWithoutEcho() {
        // readpassphrase/getpass (sudo, ssh, gpg) only clear ECHO.
        #expect(TerminalPaneView.inputMode(localFlags: canonical, foregroundIsShell: false) == .hiddenLine)
        // `read -s` in the shell itself.
        #expect(TerminalPaneView.inputMode(localFlags: canonical, foregroundIsShell: true) == .hiddenLine)
    }

    @Test func shellLineEditorIsNotAPasswordPrompt() {
        // ZLE and readline clear ECHO as well, and echo keys themselves.
        #expect(TerminalPaneView.inputMode(localFlags: 0, foregroundIsShell: true) == .shellLineEditor)
    }

    @Test func everythingElseIsOther() {
        // vim, less, ssh: raw, no local echo, not the shell.
        #expect(TerminalPaneView.inputMode(localFlags: 0, foregroundIsShell: false) == .other)
        // cat, or the shell's own `read`: echoing line input.
        #expect(TerminalPaneView.inputMode(localFlags: echo | canonical, foregroundIsShell: true) == .other)
        #expect(TerminalPaneView.inputMode(localFlags: echo | canonical, foregroundIsShell: false) == .other)
    }

    /// Waits up to 5 s for `condition`.
    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test @MainActor func zshPromptIsNotTakenForAPasswordPrompt() async throws {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.startIsolatedProcess(executable: "/bin/zsh", args: ["-f"], execName: "-zsh")
        defer { view.terminate() }
        try await eventually { view.inputMode == .shellLineEditor }
        // Its terminal has echo off, like at a password prompt — broadcast
        // must still not hand it a password typed in another pane.
        var attributes = termios()
        #expect(tcgetattr(view.process.childfd, &attributes) == 0)
        #expect(attributes.c_lflag & tcflag_t(ECHO) == 0)
        #expect(view.inputMode == .shellLineEditor)
    }

    @Test @MainActor func echoOffLineReadIsAPasswordPrompt() async throws {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.startIsolatedProcess(executable: "/bin/sh", args: ["-c", "stty -echo; exec sleep 30"])
        defer { view.terminate() }
        try await eventually { view.inputMode == .hiddenLine }
        #expect(view.inputMode == .hiddenLine)
    }

    @Test @MainActor func shellRunningReadIsNotTrustedWithBracketedPaste() async throws {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.startIsolatedProcess(executable: "/bin/zsh", args: ["-f"], execName: "-zsh")
        defer { view.terminate() }
        try await eventually { view.pasteIsBracketedByShell }
        #expect(view.pasteIsBracketedByShell)

        // The shell itself is still in the foreground, but its `read`
        // would take one line and leave the rest to the line editor.
        view.send(txt: "read x\r")
        try await eventually { view.inputMode != .shellLineEditor }
        #expect(view.inputMode == .other)
        // Some output switches the mode back on behind it.
        view.feed(text: "\u{1b}[?2004h")
        #expect(view.getTerminal().bracketedPasteMode)
        #expect(!view.pasteIsBracketedByShell)
    }
}

@Suite(.serialized) struct SecretClipboardTests {
    @MainActor private func withPasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sh_terminator-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try await body(pasteboard)
    }

    @Test @MainActor func clearsAfterItsTimer() async throws {
        try await withPasteboard { pasteboard in
            SecurityHardening.copySecret("seed words", clearAfter: 0.1, pasteboard: pasteboard)
            #expect(pasteboard.string(forType: .string) == "seed words")
            try await Task.sleep(for: .milliseconds(500))
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test @MainActor func textAndMarkersArriveAsOneItem() async {
        await withPasteboard { pasteboard in
            SecurityHardening.copySecret("seed words", pasteboard: pasteboard)
            let items = pasteboard.pasteboardItems ?? []
            #expect(items.count == 1)
            let types = Set(items.first?.types ?? [])
            #expect(types.isSuperset(of: [
                .string,
                NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
            ]))
            #expect(pasteboard.string(forType: .string) == "seed words")
        }
    }

    @Test @MainActor func lockAndQuitClearTheLastSecret() async {
        await withPasteboard { pasteboard in
            // Without a timer (or before it fires): what locking and quitting call.
            SecurityHardening.copySecret("seed words", pasteboard: pasteboard)
            SecurityHardening.clearSecretFromClipboard()
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test @MainActor func somethingCopiedSinceIsLeftAlone() async throws {
        try await withPasteboard { pasteboard in
            SecurityHardening.copySecret("seed words", clearAfter: 0.1, pasteboard: pasteboard)
            pasteboard.clearContents()
            pasteboard.setString("copied in another app", forType: .string)
            SecurityHardening.clearSecretFromClipboard()
            try await Task.sleep(for: .milliseconds(500))
            #expect(pasteboard.string(forType: .string) == "copied in another app")
        }
    }
}
