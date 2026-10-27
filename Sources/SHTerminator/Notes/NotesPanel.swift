import AppKit

/// "Notes" block under the favorites list: a plain-text field to paste
/// something into, copy it back out and delete it. Every window shows the
/// same text (`NotesStore`), and it survives restarts.
@MainActor
final class NotesPanel: NSObject, NSTextViewDelegate {
    let view = NSView()

    private let scrollView = NSScrollView()
    private let textView = NotesTextView()
    private let sectionTitle = Theme.sectionLabel("NOTES")
    private var copyButton: NSButton!
    private var clearButton: NSButton!

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
        // history and off other devices (Universal Clipboard), and don't
        // leave them on the clipboard for any app to read later.
        SecurityHardening.copySecret(textView.string, clearAfter: 20)
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
        copyButton = headerButton("doc.on.doc", "Copy All Notes", #selector(copyAll(_:)))
        clearButton = headerButton("trash", "Clear Notes (⌘Z to undo)", #selector(clearAll(_:)))

        let header = NSStackView(views: [sectionTitle, NSView(), copyButton, clearButton])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = Theme.mono(NSFont.smallSystemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        // Notes will often hold commands, keys or passwords.
        SecurityHardening.disableTextRewriting(in: textView)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        applyTheme()

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
        let button = Theme.iconButton(symbol, tip, target: self, action: action)
        button.toolTip = tip
        return button
    }

    func applyTheme() {
        sectionTitle.textColor = Theme.red
        copyButton.contentTintColor = Theme.red
        clearButton.contentTintColor = Theme.red
        textView.textColor = Theme.terminalText
        textView.insertionPointColor = Theme.red
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.hot]
        textView.backgroundColor = Theme.background
        scrollView.backgroundColor = Theme.background
    }
}

/// The notes' text view, kept to plain editing: no Services (which hand the
/// selection to other apps) and a context menu with only Cut, Copy, Paste
/// and Select All — no Look Up, Translate, Share, Speech or Writing Tools.
/// Copy and Cut put the text on the clipboard as a secret, like the "copy
/// all" button: notes often hold passwords or seed phrases.
private final class NotesTextView: NSTextView {
    private static let contextActions: Set<Selector> = [
        #selector(cut(_:)), #selector(copy(_:)), #selector(paste(_:)), #selector(selectAll(_:)),
    ]

    private var selectedText: String {
        let text = string as NSString
        return selectedRanges.map { text.substring(with: $0.rangeValue) }.joined(separator: "\n")
    }

    override func copy(_ sender: Any?) {
        SecurityHardening.copySecret(selectedText, clearAfter: 20)
    }

    override func cut(_ sender: Any?) {
        let text = selectedText
        guard !text.isEmpty else { return }
        SecurityHardening.copySecret(text, clearAfter: 20)
        // Through the normal editing path, so ⌘Z brings it back.
        delete(sender)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        for item in menu.items where !(item.action.map(Self.contextActions.contains) ?? false) {
            menu.removeItem(item)
        }
        return menu.items.isEmpty ? nil : menu
    }
}
