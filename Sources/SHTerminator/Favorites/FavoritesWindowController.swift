import AppKit

/// "Manage Favorites" panel. Categories on the left: add, rename inline
/// (the built-in group too), delete, reorder by drag. The selected
/// category's favorites on the right: edit names/commands inline, change
/// category from the popup or by dragging a row onto a category, reorder by
/// drag, and insert the selected command into the terminal window behind it.
///
/// It is an `NSPanel` on purpose: panels never become the main window, so
/// `NSApp.mainWindow` keeps pointing at the terminal window the user was
/// working in, which is where "Insert" sends the command.
@MainActor
final class FavoritesWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let categoryColumn = NSUserInterfaceItemIdentifier("category")
    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let commandColumn = NSUserInterfaceItemIdentifier("command")
    private static let movesColumn = NSUserInterfaceItemIdentifier("moveTo")
    private static let favoriteDragType = NSPasteboard.PasteboardType("dev.local.shterminator.favorite-row")
    private static let categoryDragType = NSPasteboard.PasteboardType("dev.local.shterminator.category-row")

    private let categoryTable = NSTableView()
    private let removeCategoryButton = NSButton()
    private let tableView = NSTableView()
    private let removeButton = NSButton()
    private let insertButton = NSButton()
    /// `nil` is the built-in "Uncategorized" group.
    private var selectedCategory: UUID?
    /// The selected category's favorites, as the right table shows them.
    private var shown: [Favorite] = []
    /// Set while this panel writes its own edit to the store, so the change
    /// notification doesn't reload the table under the user's next edit
    /// (e.g. after Tab from Name to Command), which would drop that edit.
    private var isSavingOwnEdit = false

    private var store: FavoritesStore { .shared }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Favorites"
        panel.minSize = NSSize(width: 640, height: 260)
        panel.hidesOnDeactivate = false
        Theme.style(window: panel)
        super.init(window: panel)
        panel.delegate = self
        // Commands may well contain hostnames, users or other sensitive bits.
        SecurityHardening.harden(window: panel)

        buildUI(in: panel)
        reloadAll()
        panel.center()

        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: FavoritesStore.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Opens the panel and starts editing a new row prefilled with
    /// `command`, in the category selected in the panel.
    func addAndEdit(command: String) {
        showWindow(nil)
        commitEditing()
        let favorite = store.add(name: "New Favorite", command: command, categoryID: selectedCategory)
        guard let row = shown.firstIndex(where: { $0.id == favorite.id }) else { return }
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
        guard let window, tableView.currentEditor() != nil || categoryTable.currentEditor() != nil else { return }
        window.makeFirstResponder(tableView)
    }

    // MARK: - UI

    private func buildUI(in panel: NSPanel) {
        let categoryColumn = NSTableColumn(identifier: Self.categoryColumn)
        categoryColumn.title = "Categories"
        categoryTable.addTableColumn(categoryColumn)
        categoryTable.headerView = nil
        categoryTable.style = .plain
        categoryTable.backgroundColor = Theme.panel
        categoryTable.allowsMultipleSelection = false
        categoryTable.allowsEmptySelection = false
        categoryTable.dataSource = self
        categoryTable.delegate = self
        categoryTable.registerForDraggedTypes([Self.favoriteDragType, Self.categoryDragType])

        let categoryScroll = NSScrollView()
        categoryScroll.documentView = categoryTable
        categoryScroll.hasVerticalScroller = true
        categoryScroll.borderType = .bezelBorder

        let addCategoryButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addCategory(_:)))
        addCategoryButton.bezelStyle = .smallSquare
        addCategoryButton.toolTip = "New Category"
        removeCategoryButton.image = NSImage(named: NSImage.removeTemplateName)
        removeCategoryButton.bezelStyle = .smallSquare
        removeCategoryButton.target = self
        removeCategoryButton.action = #selector(removeCategory(_:))
        removeCategoryButton.toolTip = "Delete Category (its favorites are kept)"
        let categoryButtons = NSStackView(views: [addCategoryButton, removeCategoryButton])
        categoryButtons.orientation = .horizontal
        categoryButtons.spacing = 6

        let nameColumn = NSTableColumn(identifier: Self.nameColumn)
        nameColumn.title = "Name"
        nameColumn.width = 170
        nameColumn.minWidth = 100
        let commandColumn = NSTableColumn(identifier: Self.commandColumn)
        commandColumn.title = "Command"
        commandColumn.minWidth = 200
        let movesColumn = NSTableColumn(identifier: Self.movesColumn)
        movesColumn.title = "Category"
        movesColumn.width = 140
        movesColumn.minWidth = 90
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(movesColumn)
        tableView.addTableColumn(commandColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.backgroundColor = Theme.background
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.registerForDraggedTypes([Self.favoriteDragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

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
        hint.font = Theme.mono(10)
        hint.textColor = Theme.muted
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
        for view in [categoryScroll, categoryButtons, scroll, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            categoryScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            categoryScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            categoryScroll.widthAnchor.constraint(equalToConstant: 170),
            categoryButtons.topAnchor.constraint(equalTo: categoryScroll.bottomAnchor, constant: 8),
            categoryButtons.leadingAnchor.constraint(equalTo: categoryScroll.leadingAnchor),
            categoryButtons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: categoryScroll.trailingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: categoryScroll.bottomAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        panel.contentView = content
    }

    private func updateButtons() {
        let hasSelection = tableView.selectedRow >= 0
        removeButton.isEnabled = hasSelection
        insertButton.isEnabled = hasSelection
        // The built-in group (always row 0) can be renamed, not deleted.
        removeCategoryButton.isEnabled = selectedCategory != nil
    }

    /// Reloads both tables, keeping the selected category and favorite.
    private func reloadAll() {
        let sections = store.sections
        if !sections.contains(where: { $0.categoryID == selectedCategory }) { selectedCategory = nil }
        categoryTable.reloadData()
        let categoryRow = sections.firstIndex { $0.categoryID == selectedCategory } ?? 0
        categoryTable.selectRowIndexes([categoryRow], byExtendingSelection: false)
        reloadFavorites()
    }

    private func reloadFavorites() {
        let selectedID = shown.indices.contains(tableView.selectedRow) ? shown[tableView.selectedRow].id : nil
        shown = store.favorites(in: selectedCategory)
        tableView.reloadData()
        if let row = shown.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
        updateButtons()
    }

    @objc private func storeDidChange(_ notification: Notification) {
        // Edits made in this panel already show the new value; reloading
        // mid-edit would cancel the field editor, so skip it then.
        guard !isSavingOwnEdit, tableView.currentEditor() == nil, categoryTable.currentEditor() == nil else { return }
        reloadAll()
    }

    // MARK: - Actions

    @objc private func addCategory(_ sender: Any?) {
        commitEditing()
        let category = store.addCategory(name: "New Category")
        selectedCategory = category.id
        reloadAll()
        let row = categoryTable.selectedRow
        categoryTable.scrollRowToVisible(row)
        categoryTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeCategory(_ sender: Any?) {
        guard let categoryID = selectedCategory, let window else { return }
        commitEditing()
        let count = store.favorites(in: categoryID).count
        guard count > 0 else {
            store.removeCategory(categoryID)
            return
        }
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the category “\(store.categoryName(categoryID))”?"
        alert.informativeText = "Its \(count == 1 ? "favorite" : "\(count) favorites") will move to “\(store.uncategorizedName)”."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.removeCategory(categoryID)
        }
    }

    @objc private func addFavorite(_ sender: Any?) {
        addAndEdit(command: "")
    }

    @objc private func removeFavorite(_ sender: Any?) {
        let row = tableView.selectedRow
        guard shown.indices.contains(row) else { return }
        window?.makeFirstResponder(tableView)
        store.remove(id: shown[row].id)
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        // Double-click on a cell edits it (handled by AppKit); double-click
        // on empty space below the rows adds a new favorite.
        if tableView.clickedRow < 0 { addFavorite(sender) }
    }

    @objc private func insertSelected(_ sender: Any?) {
        let row = tableView.selectedRow
        guard shown.indices.contains(row) else { return }
        commitEditing()
        let favorite = shown[row]
        guard let target = NSApp.mainWindow?.windowController as? PaneWindowController else {
            NSSound.beep()
            return
        }
        target.window?.makeKeyAndOrderFront(nil)
        target.insert(command: favorite.command)
    }

    @objc private func categoryPicked(_ sender: NSPopUpButton) {
        let row = tableView.row(for: sender)
        let sections = store.sections
        guard shown.indices.contains(row), sections.indices.contains(sender.indexOfSelectedItem) else { return }
        commitEditing()
        var favorite = shown[row]
        favorite.categoryID = sections[sender.indexOfSelectedItem].categoryID
        store.update(favorite)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === categoryTable ? store.sections.count : shown.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier else { return nil }
        if column == Self.movesColumn {
            return categoryPopup(for: shown[row])
        }
        let field = (tableView.makeView(withIdentifier: column, owner: self) as? NSTextField) ?? {
            let field = PlainTextField()
            field.identifier = column
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.delegate = self
            return field
        }()
        switch column {
        case Self.categoryColumn:
            field.stringValue = store.sections[row].name
            field.font = Theme.mono(12, .semibold)
            field.textColor = Theme.red
        case Self.nameColumn:
            field.stringValue = shown[row].name
            field.font = Theme.mono(12, .semibold)
            field.textColor = Theme.red
        default:
            field.stringValue = shown[row].command
            field.font = Theme.mono(12)
            field.textColor = Theme.terminalText
        }
        return field
    }

    private func categoryPopup(for favorite: Favorite) -> NSPopUpButton {
        let popup = (tableView.makeView(withIdentifier: Self.movesColumn, owner: self) as? NSPopUpButton) ?? {
            let popup = NSPopUpButton()
            popup.identifier = Self.movesColumn
            popup.isBordered = false
            popup.controlSize = .small
            popup.font = Theme.mono(10)
            popup.target = self
            popup.action = #selector(categoryPicked(_:))
            return popup
        }()
        let sections = store.sections
        popup.removeAllItems()
        // Titles may repeat; add items one by one so none are merged.
        for section in sections {
            popup.menu?.addItem(NSMenuItem(title: section.name, action: nil, keyEquivalent: ""))
        }
        popup.selectItem(at: sections.firstIndex { $0.categoryID == favorite.categoryID } ?? 0)
        return popup
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === categoryTable {
            let sections = store.sections
            let row = categoryTable.selectedRow
            let category = sections.indices.contains(row) ? sections[row].categoryID : nil
            if category != selectedCategory {
                selectedCategory = category
                tableView.deselectAll(nil)
                reloadFavorites()
            }
        }
        updateButtons()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        isSavingOwnEdit = true
        defer { isSavingOwnEdit = false }
        if field.identifier == Self.categoryColumn {
            let sections = store.sections
            let row = categoryTable.row(for: field)
            guard sections.indices.contains(row) else { return }
            store.renameCategory(sections[row].categoryID, to: field.stringValue)
            // A blank name is refused: show the kept one again.
            field.stringValue = store.categoryName(sections[row].categoryID)
            // Category popups in the favorites table show the new name.
            tableView.reloadData(forRowIndexes: IndexSet(shown.indices), columnIndexes: [tableView.column(withIdentifier: Self.movesColumn)])
            return
        }
        let row = tableView.row(for: field)
        guard shown.indices.contains(row) else { return }
        var favorite = shown[row]
        if field.identifier == Self.nameColumn {
            favorite.name = field.stringValue
        } else {
            favorite.command = field.stringValue
        }
        store.update(favorite)
        shown[row] = favorite
    }

    // MARK: - Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        if tableView === categoryTable {
            // The built-in group stays first.
            guard row > 0 else { return nil }
            item.setString(String(row), forType: Self.categoryDragType)
        } else {
            item.setString(shown[row].id.uuidString, forType: Self.favoriteDragType)
        }
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        if tableView === categoryTable {
            if pasteboard.string(forType: Self.favoriteDragType) != nil {
                // A favorite dropped on a category moves into it.
                guard dropOperation == .on, store.sections.indices.contains(row) else { return [] }
                return .move
            }
            // Categories reorder among themselves, below the built-in group.
            guard pasteboard.string(forType: Self.categoryDragType) != nil else { return [] }
            tableView.setDropRow(max(row, 1), dropOperation: .above)
            return .move
        }
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard
        if let string = pasteboard.string(forType: Self.favoriteDragType), let id = UUID(uuidString: string), var favorite = store.favorite(id: id) {
            if tableView === categoryTable {
                let sections = store.sections
                guard sections.indices.contains(row) else { return false }
                favorite.categoryID = sections[row].categoryID
                store.update(favorite)
                return true
            }
            guard let source = shown.firstIndex(where: { $0.id == id }) else { return false }
            let destination = source < row ? row - 1 : row
            guard destination != source else { return false }
            store.move(id: id, to: destination)
            tableView.selectRowIndexes([destination], byExtendingSelection: false)
            updateButtons()
            return true
        }
        if tableView === categoryTable, let string = pasteboard.string(forType: Self.categoryDragType), let sourceRow = Int(string) {
            // Rows count the built-in group; `categories` doesn't.
            let source = sourceRow - 1
            let destination = (sourceRow < row ? row - 1 : row) - 1
            guard source != destination else { return false }
            store.moveCategory(from: source, to: destination)
            return true
        }
        return false
    }
}
