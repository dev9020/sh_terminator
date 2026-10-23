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

    @Test func typedTextNeverEndsALineUnlessAllowed() {
        let text = "echo a\n\nrm -rf ~\n"
        #expect(PastePolicy.typedText(text, bracketedPaste: false, runsLines: false) == "echo a rm -rf ~")
        #expect(PastePolicy.typedText(text, bracketedPaste: true, runsLines: false) == text)
        #expect(PastePolicy.typedText(text, bracketedPaste: false, runsLines: true) == text)
    }

    @Test func typedTextAlwaysDropsControlCharacters() {
        // E.g. a favorite or broadcast paste carrying an early end of bracketed paste.
        let evil = "ls\u{1b}[201~\rwhoami"
        #expect(PastePolicy.typedText(evil, bracketedPaste: true, runsLines: false) == "ls[201~\rwhoami")
        #expect(PastePolicy.typedText(evil, bracketedPaste: false, runsLines: false) == "ls[201~ whoami")
    }
}
