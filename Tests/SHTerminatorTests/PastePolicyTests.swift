import Testing
@testable import SHTerminator

@Suite struct PastePolicyTests {
    @Test func plainSingleLineNeedsNoConfirmation() {
        #expect(PastePolicy.concern(for: "ls -la", bracketedPaste: false) == nil)
        #expect(PastePolicy.concern(for: "ls -la", bracketedPaste: true) == nil)
    }

    @Test func lineBreaksMatterOnlyWithoutBracketedPaste() {
        #expect(PastePolicy.concern(for: "a\nb\n", bracketedPaste: false) == .runsLines(2))
        #expect(PastePolicy.concern(for: "a\nb\n", bracketedPaste: true) == nil)
    }

    @Test func crlfCountsAsOneLineBreak() {
        #expect(PastePolicy.lineBreakCount(in: "a\r\nb") == 1)
    }

    @Test func escapeIsAlwaysFlagged() {
        // The classic bracketed-paste escape: end the paste, then run a command.
        let evil = "echo hi\u{1b}[201~rm -rf ~\n"
        #expect(PastePolicy.concern(for: evil, bracketedPaste: true) == .controlCharacters(1))
        #expect(PastePolicy.strippingControlCharacters(evil) == "echo hi[201~rm -rf ~\n")
    }

    @Test func tabIsAllowedButC1AndDelAreNot() {
        #expect(PastePolicy.concern(for: "a\tb", bracketedPaste: true) == nil)
        #expect(PastePolicy.concern(for: "a\u{9b}b\u{7f}", bracketedPaste: true) == .controlCharacters(2))
    }
}
