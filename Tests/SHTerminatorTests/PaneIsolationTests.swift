import AppKit
import Testing
@testable import SHTerminator

@Suite struct PaneIsolationTests {
    /// Open file paths of `pid`, as `lsof` lists them.
    private func openPaths(of pid: pid_t) throws -> [String] {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-n", "-P", "-p", String(pid), "-F", "n"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        try lsof.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()
        return String(decoding: output, as: UTF8.self).split(separator: "\n")
            .filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }

    @Test @MainActor func aLaterPaneCannotReachAnEarlierOnesTerminal() throws {
        let first = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        first.startIsolatedProcess(executable: "/bin/sleep", args: ["30"])
        defer { first.terminate() }
        let fd = first.process.childfd
        #expect(fd >= 0)
        #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)

        let second = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        second.startIsolatedProcess(executable: "/bin/sleep", args: ["30"])
        defer { second.terminate() }
        // A child holds only its own terminal's other end (/dev/ttysNNN);
        // a /dev/ptmx would be another pane's.
        let paths = try openPaths(of: second.process.shellPid)
        #expect(paths.contains { $0.hasPrefix("/dev/ttys") })
        #expect(!paths.contains("/dev/ptmx"))
    }
}

@Suite struct BracketedPasteTrustTests {
    @Test @MainActor func onlyTheShellsOwnPromptIsTrusted() {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        // Any output can switch the mode on…
        view.feed(text: "\u{1b}[?2004h")
        #expect(view.getTerminal().bracketedPasteMode)
        // …but with no shell at its prompt behind it, it isn't believed.
        #expect(!view.pasteIsBracketedByShell)

        view.startIsolatedProcess(executable: "/bin/sleep", args: ["30"])
        defer { view.terminate() }
        #expect(!view.pasteIsBracketedByShell)
    }

    @Test @MainActor func zshAtItsPromptIsTrusted() async throws {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        // As a pane starts it: a login shell, here without any rc files.
        view.startIsolatedProcess(executable: "/bin/zsh", args: ["-f"], execName: "-zsh")
        defer { view.terminate() }
        for _ in 0..<50 where !view.pasteIsBracketedByShell {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(view.getTerminal().bracketedPasteMode)
        #expect(view.pasteIsBracketedByShell)
    }
}
