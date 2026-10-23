import AppKit
import Testing
@testable import SHTerminator

@Suite struct LinkPolicyTests {
    @Test func webAndMailLinksOpen() {
        #expect(LinkPolicy.url(for: "https://example.com/a?b=c") != nil)
        #expect(LinkPolicy.url(for: "HTTP://example.com") != nil)
        #expect(LinkPolicy.url(for: "mailto:someone@example.com") != nil)
    }

    @Test func filesAppsAndCustomSchemesDoNot() {
        #expect(LinkPolicy.url(for: "file:///tmp/x.command") == nil)
        #expect(LinkPolicy.url(for: "/Applications/Calculator.app") == nil)
        #expect(LinkPolicy.url(for: "~/Downloads/run.command") == nil)
        #expect(LinkPolicy.url(for: "x-apple.systempreferences:com.apple.preference.security") == nil)
        #expect(LinkPolicy.url(for: "ssh://evil.example") == nil)
    }

    @Test func shownDestinationCannotHideOrReorderAnything() throws {
        // A right-to-left override would make the end of the link read first.
        let url = try #require(LinkPolicy.url(for: "https://example.com/\u{202E}gpj.exe"))
        let shown = HostRequestFilter.shownDestination(url)
        #expect(shown.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 })

        let long = try #require(LinkPolicy.url(for: "https://example.com/" + String(repeating: "a", count: 5000)))
        #expect(HostRequestFilter.shownDestination(long).count == HostRequestFilter.maxShownLinkLength + 1)
    }
}

@Suite struct HostRequestFilterTests {
    @Test @MainActor func clipboardIsOffLimitsToThePaneProgram() throws {
        let view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let filter = try #require(view.terminalDelegate as? HostRequestFilter)
        #expect(filter.clipboardRead(source: view) == nil)

        // OSC 52 write: must not reach the system clipboard.
        let marker = "sh_terminator-test-\(UUID().uuidString)"
        let base64 = Data(marker.utf8).base64EncodedString()
        view.feed(text: "\u{1b}]52;c;\(base64)\u{07}")
        #expect(NSPasteboard.general.string(forType: .string) != marker)
    }
}

@Suite struct PaneTitleTests {
    @Test func controlAndBidiCharactersAreDropped() {
        #expect(PaneSession.displayTitle("vim\u{1b}[31m\nnotes\u{202E}txt.exe") == "vim[31mnotestxt.exe")
    }

    @Test func invisibleCharactersAreDropped() {
        // Zero-width space and joiner, word joiner, BOM, a tag character.
        #expect(PaneSession.displayTitle("ssh\u{200B} pr\u{200D}od\u{2060}\u{FEFF}\u{E0041}") == "ssh prod")
    }

    @Test func emptyAfterCleanupMeansNoTitle() {
        #expect(PaneSession.displayTitle("\u{07}\u{1b}  ") == nil)
    }

    @Test func longTitlesAreCut() {
        let title = PaneSession.displayTitle(String(repeating: "a", count: 1000))
        #expect(title?.count == PaneSession.maxTitleLength)
    }
}
