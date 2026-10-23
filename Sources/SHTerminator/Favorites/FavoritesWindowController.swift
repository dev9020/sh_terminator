import AppKit

/// "Manage Favorites" panel: edit names/commands inline, add, remove, reorder
/// by drag, and insert the selected command into the terminal window behind it.
///
/// It is an `NSPanel` on purpose: panels never become the main window, so
/// `NSApp.mainWindow` keeps pointing at the terminal window the user was
/// working in, which is where "Insert" sends the command.
@MainActor
final class FavoritesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let commandColumn = NSUserInterfaceItemIdentifier("command")
    private static let rowDragType = NSPasteboard.PasteboardType("dev.local.shterminator.favorite-row")

    private let tableView = NSTableView()
    private let removeButton = NSButton()
    private let insertButton = NSButton()
    /// Set while this panel writes its own edit to the store, so the change
    /// notification doesn't reload the table under the user's next edit
    /// (e.g. after Tab from Name to Command), which would drop that edit.
    private var isSavingOwnEdit = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Favorites"
        panel.minSize = NSSize(width: 480, height: 240)
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        // Commands may well contain hostnames, users or other sensitive bits.
        SecurityHardening.harden(window: panel)

        buildUI(in: panel)
        panel.center()

        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: FavoritesStore.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Opens the panel and starts editing a new row prefilled with `command`.
    func addAndEdit(command: String) {
        showWindow(nil)
        let favorite = FavoritesStore.shared.add(name: "New Favorite", command: command)
        guard let row = FavoritesStore.shared.items.firstIndex(where: { $0.id == favorite.id }) else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window { SecurityHardening.harden(window: window) }
    }

    // Closing the panel or switching to the terminal mid-edit must still
    // save what was typed: ending first responder commits the field editor.
    func windowDidResignKey(_ notification: Notification) {
        commitEditing()
    }

    func windowWillClose(_ notification: Notification) {
        commitEditing()
    }

    private func commitEditing() {
        guard let window, tableView.currentEditor() != nil else { return }
        window.makeFirstResponder(tableView)
    }

    // MARK: - UI

    private func buildUI(in panel: NSPanel) {
        let nameColumn = NSTableColumn(identifier: Self.nameColumn)
        nameColumn.title = "Name"
        nameColumn.width = 180
        nameColumn.minWidth = 100
        let commandColumn = NSTableColumn(identifier: Self.commandColumn)
        commandColumn.title = "Command"
        commandColumn.minWidth = 200
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(commandColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.registerForDraggedTypes([Self.rowDragType])

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let addButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addFavorite(_:)))
        addButton.bezelStyle = .smallSquare
        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removeFavorite(_:))

        let hint = NSTextField(labelWithString: "Commands are inserted at the prompt, never run. Press Return in the terminal yourself.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        insertButton.title = "Insert into Terminal"
        insertButton.bezelStyle = .rounded
        insertButton.keyEquivalent = "\r"
        insertButton.keyEquivalentModifierMask = [.command]
        insertButton.target = self
        insertButton.action = #selector(insertSelected(_:))

        let bottom = NSStackView(views: [addButton, removeButton, hint, insertButton])
        bottom.orientation = .horizontal
        bottom.spacing = 6
        bottom.setCustomSpacing(12, after: removeButton)

        let content = NSView()
        for view in [scroll, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        panel.contentView = content
        updateButtons()
    }

    private func updateButtons() {
        let hasSelection = tableView.selectedRow >= 0
        removeButton.isEnabled = hasSelection
        insertButton.isEnabled = hasSelection
    }

    @objc private func storeDidChange(_ notification: Notification) {
        // Edits made in this panel already show the new value; reloading
        // mid-edit would cancel the field editor, so skip it then.
        guard !isSavingOwnEdit, tableView.currentEditor() == nil else { return }
        let selected = tableView.selectedRow
        tableView.reloadData()
        if selected >= 0, selected < tableView.numberOfRows {
            tableView.selectRowIndexes([selected], byExtendingSelection: false)
        }
        updateButtons()
    }

    // MARK: - Actions

    @objc private func addFavorite(_ sender: Any?) {
        addAndEdit(command: "")
    }

    @objc private func removeFavorite(_ sender: Any?) {
        let row = tableView.selectedRow
        guard FavoritesStore.shared.items.indices.contains(row) else { return }
        window?.makeFirstResponder(tableView)
        FavoritesStore.shared.remove(id: FavoritesStore.shared.items[row].id)
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        // Double-click on a cell edits it (handled by AppKit); double-click
        // on empty space below the rows adds a new favorite.
        if tableView.clickedRow < 0 { addFavorite(sender) }
    }

    @objc private func insertSelected(_ sender: Any?) {
        let row = tableView.selectedRow
        guard FavoritesStore.shared.items.indices.contains(row) else { return }
        commitEditing()
        let favorite = FavoritesStore.shared.items[row]
        guard let target = NSApp.mainWindow?.windowController as? PaneWindowController else {
            NSSound.beep()
            return
        }
        target.window?.makeKeyAndOrderFront(nil)
        target.insert(command: favorite.command)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        FavoritesStore.shared.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier else { return nil }
        let field = (tableView.makeView(withIdentifier: column, owner: self) as? NSTextField) ?? {
            let field = NSTextField()
            field.identifier = column
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.delegate = self
            return field
        }()
        let favorite = FavoritesStore.shared.items[row]
        if column == Self.nameColumn {
            field.stringValue = favorite.name
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
        } else {
            field.stringValue = favorite.command
            field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard FavoritesStore.shared.items.indices.contains(row) else { return }
        var favorite = FavoritesStore.shared.items[row]
        if field.identifier == Self.nameColumn {
            favorite.name = field.stringValue
        } else {
            favorite.command = field.stringValue
        }
        isSavingOwnEdit = true
        FavoritesStore.shared.update(favorite)
        isSavingOwnEdit = false
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let string = info.draggingPasteboard.string(forType: Self.rowDragType), let source = Int(string) else { return false }
        let destination = source < row ? row - 1 : row
        guard destination != source else { return false }
        FavoritesStore.shared.move(from: source, to: destination)
        tableView.selectRowIndexes([destination], byExtendingSelection: false)
        return true
    }
}
