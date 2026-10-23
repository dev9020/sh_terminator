import Foundation

/// Decides whether a paste into a pane needs the user's confirmation first.
///
/// Two classic ways a "harmless" copied snippet bites:
/// - **Control characters.** An ESC can carry `ESC[201~`, which ends a
///   bracketed paste early so the rest of the text is typed as if by hand —
///   newlines included — and other control bytes can drive the program in
///   the pane. These are never pasted without asking.
/// - **Line breaks without bracketed paste.** If the program in the pane
///   hasn't enabled bracketed paste, every line break acts as Return and runs
///   what came before it. With bracketed paste on (zsh/bash/fish at a prompt)
///   the shell just inserts the lines for review, so no question is asked.
enum PastePolicy {
    enum Concern: Equatable {
        /// The text has this many control characters other than tab/CR/LF.
        case controlCharacters(Int)
        /// Pasting would press Return this many times.
        case runsLines(Int)
    }

    static func concern(for text: String, bracketedPaste: Bool) -> Concern? {
        let controls = text.unicodeScalars.filter(isDisallowedControl).count
        if controls > 0 { return .controlCharacters(controls) }
        if !bracketedPaste {
            let breaks = lineBreakCount(in: text)
            if breaks > 0 { return .runsLines(breaks) }
        }
        return nil
    }

    /// `text` without the control characters `concern` objects to.
    static func strippingControlCharacters(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !isDisallowedControl($0) })
        return String(scalars)
    }

    /// C0 controls except tab, LF and CR; DEL; and the C1 range (which some
    /// terminals treat as 8-bit escape sequence introducers).
    static func isDisallowedControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D: return false
        case 0x00...0x1F, 0x7F, 0x80...0x9F: return true
        default: return false
        }
    }

    /// CRLF counts once, like a terminal would see it as one Return.
    static func lineBreakCount(in text: String) -> Int {
        text.reduce(0) { $1.isNewline ? $0 + 1 : $0 }
    }
}
