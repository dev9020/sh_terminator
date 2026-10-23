import AppKit

/// Scrollable list of favorites shown at the side of a terminal window — one
/// per window, shared by all of its panes. A click hands the command to
/// `onPick`; the window inserts it into its focused pane.
///
/// The table refuses first responder, so clicking a row never takes keyboard
/// focus away from the terminal. Under the list, behind a draggable
/// divider, sits the shared `NotesPanel`.
@MainActor
final class FavoritesSidebar: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    var onPick: ((Favorite) -> Void)?

    private let tableView = NSTableView()
    private let notes = NotesPanel()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No favorites yet.\nAdd one with ⌘⇧F, or select a command in the terminal and press ⌘⇧S.")

    override init() {
        super.init()
        buildUI()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: FavoritesStore.didChange, object: nil)
    }

    @objc private func storeDidChange(_ notification: Notification) {
        reload()
    }

    private func reload() {
        tableView.reloadData()
        emptyLabel.isHidden = !FavoritesStore.shared.items.isEmpty
    }

    // MARK: - UI

    private func buildUI() {
        let title = NSTextField(labelWithString: "FAVORITES")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let manage = NSButton(image: NSImage(systemSymbolName: "pencil", accessibilityDescription: "Manage Favorites")!, target: nil, action: #selector(AppDelegate.showFavorites(_:)))
        manage.target = AppDelegate.shared
        manage.isBordered = false
        manage.toolTip = "Manage Favorites… (⌘⇧F)"
        manage.refusesFirstResponder = true

        let header = NSStackView(views: [title, NSView(), manage])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("favorite"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 40
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow

        let favoritesPane = NSView()
        for subview in [header, scroll, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            favoritesPane.addSubview(subview)
        }

        // Favorites on top, notes below; the divider between them can be
        // dragged (holding priorities stay below the drag priority).
        let split = FractionSplitView(firstFraction: 0.6)
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(favoritesPane)
        split.addArrangedSubview(notes.view)
        split.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)

        for subview in [background, split] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.topAnchor.constraint(equalTo: view.topAnchor),
            split.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            favoritesPane.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            header.topAnchor.constraint(equalTo: favoritesPane.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: favoritesPane.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: favoritesPane.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: favoritesPane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: favoritesPane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: favoritesPane.bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(equalTo: favoritesPane.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: favoritesPane.trailingAnchor, constant: -16),
        ])
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard FavoritesStore.shared.items.indices.contains(row) else { return }
        onPick?(FavoritesStore.shared.items[row])
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        FavoritesStore.shared.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: FavoriteCell.identifier, owner: self) as? FavoriteCell) ?? FavoriteCell()
        let favorite = FavoritesStore.shared.items[row]
        cell.nameLabel.stringValue = row < 9 ? "\(favorite.name)  ⌘\(row + 1)" : favorite.name
        cell.commandLabel.stringValue = favorite.command
        cell.toolTip = favorite.command
        return cell
    }
}

private final class FavoriteCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FavoriteCell")

    let nameLabel = NSTextField(labelWithString: "")
    let commandLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        commandLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        commandLabel.textColor = .secondaryLabelColor
        commandLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [nameLabel, commandLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            commandLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
        for label in [nameLabel, commandLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// A two-pane `NSSplitView` that puts its divider at `firstFraction` of its
/// size on first layout, then behaves like a normal draggable split view.
private final class FractionSplitView: NSSplitView {
    private let firstFraction: CGFloat
    private var didSetInitialPosition = false

    init(firstFraction: CGFloat) {
        self.firstFraction = firstFraction
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        let total = isVertical ? bounds.width : bounds.height
        guard !didSetInitialPosition, subviews.count == 2, total > 0 else { return }
        didSetInitialPosition = true
        setPosition(total * firstFraction, ofDividerAt: 0)
    }
}
