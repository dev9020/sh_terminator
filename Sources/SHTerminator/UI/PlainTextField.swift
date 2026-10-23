import AppKit

/// An editable text field that never rewrites what is typed into it (see
/// `SecurityHardening.disableTextRewriting`). AppKit edits every field of a
/// window with one shared field editor, which follows the system-wide
/// smart quotes / autocorrect settings, so it is set up each time this
/// field starts editing.
final class PlainTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let editor = currentEditor() as? NSTextView {
            SecurityHardening.disableTextRewriting(in: editor)
        }
        return true
    }
}

/// `PlainTextField` for a search field.
final class PlainSearchField: NSSearchField {
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let editor = currentEditor() as? NSTextView {
            SecurityHardening.disableTextRewriting(in: editor)
        }
        return true
    }
}
