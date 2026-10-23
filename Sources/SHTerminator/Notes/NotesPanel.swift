import AppKit

/// "Notes" block under the favorites list: a plain-text field to paste
/// something into, copy it back out and delete it. Every window shows the
/// same text (`NotesStore`), and it survives restarts.
@MainActor
final class NotesPanel: NSObject, NSTextViewDelegate {
    let view = NSView()

    private let scrollView = NSTextView.scrollableTextView()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }

    override init() {
        super.init()
        buildUI()
        textView.string = NotesStore.shared.text
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: NotesStore.didChange, object: nil)
    }

    @objc private func storeDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? !== self else { return }
        textView.string = NotesStore.shared.text
    }

    func textDidChange(_ notification: Notification) {
        NotesStore.shared.setText(textView.string, from: self)
    }

    // MARK: - Actions

    @objc private func copyAll(_ sender: Any?) {
        // Notes often hold secrets: keep them out of clipboard managers'
        // history and off other devices (Universal Clipboard).
        SecurityHardening.copySecret(textView.string)
    }

    @objc private func clearAll(_ sender: Any?) {
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        guard all.length > 0 else { return }
        // Goes through the normal editing path so ⌘Z can bring it back.
        if textView.shouldChangeText(in: all, replacementString: "") {
            textView.replaceCharacters(in: all, with: "")
            textView.didChangeText()
        }
    }

    // MARK: - UI

    private func buildUI() {
        let title = NSTextField(labelWithString: "NOTES")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let copy = headerButton("doc.on.doc", "Copy All Notes", #selector(copyAll(_:)))
        let clear = headerButton("trash", "Clear Notes (⌘Z to undo)", #selector(clearAll(_:)))

        let header = NSStackView(views: [title, NSView(), copy, clear])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        let textView = self.textView
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        // Notes will often hold commands, keys or passwords: no spelling or
        // grammar checks and no "smart" rewriting of what was pasted.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5)

        for subview in [header, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func headerButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        button.isBordered = false
        button.toolTip = tip
        button.refusesFirstResponder = true
        return button
    }
}
