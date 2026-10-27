import AppKit

/// A one-line list of the main keyboard shortcuts along the bottom of a
/// terminal window, under both the panes and the favorites sidebar. Fixed
/// text only. View → Show Shortcuts Bar (⌘/) turns the list off; protections
/// that are off (`AppSettings.weakenedProtections`) are always shown in it,
/// as the settings can be changed from outside the app.
final class ShortcutsBar: NSView {
    static let height: CGFloat = 22

    private static let shortcuts: [(String, String)] = [
        ("⌘N", "window"),
        ("⌘D/⌘⇧D", "split"),
        ("⌘W", "close"),
        ("⌘[ ⌘]", "pane"),
        ("⌥⌘←→↑↓", "move"),
        ("⌘↩", "zoom"),
        ("⌥⌘I", "broadcast"),
        ("⌘F", "find"),
        ("⌘K", "clear"),
        ("⌥⌘C", "secure copy"),
        ("⌘1…9", "favorite"),
        ("⌘⇧B", "sidebar"),
        ("⌃⌘L", "lock"),
    ]

    private let label = NSTextField(labelWithString: "")
    private let border = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        border.wantsLayer = true
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        applyTheme()

        label.maximumNumberOfLines = 1
        label.toolTip = Self.shortcuts.map { "\($0.0)  \($0.1)" }.joined(separator: "\n")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(showsShortcuts: Bool, weakened: [String]) {
        label.attributedStringValue = Self.text(showsShortcuts: showsShortcuts, weakened: weakened)
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.panel.cgColor
        border.layer?.backgroundColor = Theme.faintRed.cgColor
    }

    private static func text(showsShortcuts: Bool, weakened: [String]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let key: [NSAttributedString.Key: Any] = [.font: Theme.mono(10, .bold), .foregroundColor: Theme.red, .paragraphStyle: style]
        let description: [NSAttributedString.Key: Any] = [.font: Theme.mono(10), .foregroundColor: Theme.muted, .paragraphStyle: style]
        let separator: [NSAttributedString.Key: Any] = [.font: Theme.mono(10), .foregroundColor: Theme.dimRed, .paragraphStyle: style]

        let warning: [NSAttributedString.Key: Any] = [.font: Theme.mono(10, .bold), .foregroundColor: Theme.hot, .paragraphStyle: style]

        let text = NSMutableAttributedString()
        if !weakened.isEmpty {
            text.append(NSAttributedString(string: "⚠ " + weakened.joined(separator: " · "), attributes: warning))
            if showsShortcuts { text.append(NSAttributedString(string: "  //  ", attributes: separator)) }
        }
        guard showsShortcuts else { return text }
        text.append(NSAttributedString(string: "// KEYS  ", attributes: key))
        for (index, (keys, action)) in shortcuts.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "  ·  ", attributes: separator)) }
            text.append(NSAttributedString(string: keys, attributes: key))
            text.append(NSAttributedString(string: " " + action, attributes: description))
        }
        return text
    }
}

/// A terminal window's content view: the panes and sidebar on top, the
/// `ShortcutsBar` along the bottom (when shown).
final class WindowContentView: NSView {
    let main: NSView
    let shortcutsBar = ShortcutsBar()

    init(main: NSView) {
        self.main = main
        super.init(frame: .zero)
        addSubview(main)
        addSubview(shortcutsBar)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows the shortcuts per `AppSettings.showShortcutsBar`, and the bar
    /// itself whenever there is that or a weakened protection to show.
    @MainActor func updateShortcutsBar() {
        let weakened = AppSettings.weakenedProtections
        shortcutsBar.update(showsShortcuts: AppSettings.showShortcutsBar, weakened: weakened)
        shortcutsBar.isHidden = !AppSettings.showShortcutsBar && weakened.isEmpty
        placeSubviews()
    }

    func applyTheme() {
        shortcutsBar.applyTheme()
        updateShortcutsBar()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        placeSubviews()
    }

    func placeSubviews() {
        let barHeight = shortcutsBar.isHidden ? 0 : ShortcutsBar.height
        shortcutsBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        main.frame = NSRect(x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
    }
}
