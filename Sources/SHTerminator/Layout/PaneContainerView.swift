import AppKit

/// One pane on screen: a slim header with what's running where, above the
/// terminal itself. The focus ring is drawn around the whole thing.
@MainActor
final class PaneContainerView: NSView {
    let session: PaneSession
    private let titleLabel = NSTextField(labelWithString: "")
    private let header = NSView()

    static let headerHeight: CGFloat = 18

    init(session: PaneSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 2

        header.wantsLayer = true
        titleLabel.font = Theme.mono(10, .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .center
        // Below NSSplitView's holding priority (250): otherwise the label's
        // default hugging (251) wins over the split view's sizes and shrinks
        // a nested split's column to the width of its title.
        titleLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        titleLabel.setContentHuggingPriority(.init(1), for: .horizontal)

        let terminal = session.terminalView
        for view in [header, titleLabel, terminal] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        header.addSubview(titleLabel)
        addSubview(header)
        addSubview(terminal)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(title: "", focused: false, broadcasting: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(title: String, focused: Bool, broadcasting: Bool) {
        let marker = focused ? "▸ " : ""
        titleLabel.stringValue = broadcasting ? "⦿ BROADCAST · " + title : marker + title
        titleLabel.textColor = broadcasting || focused ? Theme.hot : Theme.muted
        header.layer?.backgroundColor = broadcasting
            ? Theme.red.withAlphaComponent(0.35).cgColor
            : focused ? Theme.red.withAlphaComponent(0.14).cgColor : Theme.panel.cgColor
        layer?.borderColor = focused ? Theme.red.cgColor : Theme.background.cgColor
    }
}
