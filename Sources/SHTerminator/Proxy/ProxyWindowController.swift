import AppKit

/// "Proxy" panel: the SOCKS5 proxies the user has added (add, edit, delete,
/// pick the one in use, or none) and which programs in the panes go
/// through it. See `ProxyStore` for how it reaches them.
@MainActor
final class ProxyWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static let useColumn = NSUserInterfaceItemIdentifier("use")
    private static let addressColumn = NSUserInterfaceItemIdentifier("address")

    private let tableView = NSTableView()
    private let removeButton = NSButton()
    private let editButton = NSButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var toolBoxes: [ProxyTool: NSButton] = [:]

    /// The fields of the add/edit dialog while it is open, so a URL pasted
    /// into its first field can fill in the rest.
    @MainActor private struct EditFields {
        let url = PlainTextField()
        let host = PlainTextField()
        let port = PlainTextField()
        let user = PlainTextField()
        let password = NSSecureTextField()
        let remoteDNS = NSButton(checkboxWithTitle: "Look up server names through the proxy (socks5h)", target: nil, action: nil)
    }
    private var editFields: EditFields?

    private var store: ProxyStore { .shared }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Proxy"
        panel.minSize = NSSize(width: 460, height: 380)
        panel.hidesOnDeactivate = false
        Theme.style(window: panel)
        super.init(window: panel)
        panel.delegate = self
        // Proxy addresses and user names are nobody else's business either.
        SecurityHardening.harden(window: panel)

        buildUI(in: panel)
        reload()
        panel.center()

        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: ProxyStore.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window { SecurityHardening.harden(window: window) }
    }

    // MARK: - UI

    private func buildUI(in panel: NSPanel) {
        let useColumn = NSTableColumn(identifier: Self.useColumn)
        useColumn.title = "Use"
        useColumn.width = 36
        useColumn.minWidth = 36
        useColumn.maxWidth = 36
        let addressColumn = NSTableColumn(identifier: Self.addressColumn)
        addressColumn.title = "Proxy"
        addressColumn.minWidth = 200
        tableView.addTableColumn(useColumn)
        tableView.addTableColumn(addressColumn)
        tableView.style = .plain
        tableView.backgroundColor = Theme.panel
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editSelected(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let addButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addProxy(_:)))
        addButton.bezelStyle = .smallSquare
        addButton.toolTip = "Add Proxy"
        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        removeButton.toolTip = "Delete Proxy"
        editButton.title = "Edit…"
        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editSelected(_:))
        let listButtons = NSStackView(views: [addButton, removeButton, editButton])
        listButtons.orientation = .horizontal
        listButtons.spacing = 6

        let toolsTitle = Theme.sectionLabel("SEND THROUGH THE PROXY")
        let toolTitles: [ProxyTool: String] = [.curl: "curl", .git: "git", .brew: "brew", .ssh: "ssh, scp, sftp"]
        let toolsRow = NSStackView()
        toolsRow.orientation = .horizontal
        toolsRow.spacing = 16
        for tool in ProxyTool.allCases {
            let box = NSButton(checkboxWithTitle: toolTitles[tool] ?? tool.rawValue, target: self, action: #selector(toolToggled(_:)))
            box.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolBoxes[tool] = box
            toolsRow.addArrangedSubview(box)
        }

        statusLabel.font = Theme.mono(11, .bold)

        let info = NSTextField(wrappingLabelWithString: """
            Applies to every zsh pane from its next command on; one proxy at a time. \
            curl, git (https and ssh remotes) and brew get it from all_proxy/https_proxy; \
            ssh, scp and sftp through a helper set as ProxyCommand. \
            Passwords are saved in a file only you can read (proxies.json, 0600); a wrapped program sees the proxy URL, \
            password included, in its environment. \
            Through a proxy you don't run yourself, check the server's key fingerprint \
            the first time you connect with ssh.
            """)
        info.font = Theme.mono(10)
        info.textColor = Theme.muted

        let content = NSStackView(views: [scroll, listButtons, toolsTitle, toolsRow, statusLabel, info])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.setCustomSpacing(18, after: listButtons)
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            info.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            statusLabel.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func reload() {
        let selected = selectedEntry?.id
        tableView.reloadData()
        if let selected, let row = store.proxies.firstIndex(where: { $0.id == selected }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
        for (tool, box) in toolBoxes {
            box.state = store.tools.contains(tool) ? .on : .off
        }
        updateStatus()
        updateButtons()
    }

    private func updateStatus() {
        if let reason = store.unavailableReason(loginShell: PaneSession.loginShellPath()) {
            statusLabel.stringValue = "Panes: no proxy (\(reason))"
            statusLabel.textColor = Theme.red
        } else if let active = store.active, !store.tools.isEmpty {
            let tools = ProxyTool.allCases.filter { store.tools.contains($0) }.map(\.rawValue).joined(separator: ", ")
            statusLabel.stringValue = "Panes: \(active.scheme) \(active.address) for \(tools)"
            statusLabel.textColor = Theme.hot
        } else {
            statusLabel.stringValue = store.active == nil ? "Panes: no proxy (none in use)" : "Panes: no proxy (no program chosen)"
            statusLabel.textColor = Theme.muted
        }
    }

    private func updateButtons() {
        removeButton.isEnabled = selectedEntry != nil
        editButton.isEnabled = selectedEntry != nil
    }

    private var selectedEntry: ProxyEntry? {
        store.proxies.indices.contains(tableView.selectedRow) ? store.proxies[tableView.selectedRow] : nil
    }

    @objc private func storeDidChange(_ notification: Notification) {
        reload()
    }

    // MARK: - Actions

    @objc private func addProxy(_ sender: Any?) {
        guard let (entry, password) = runEditDialog(editing: nil) else { return }
        store.add(entry, password: password ?? "")
        if let row = store.proxies.firstIndex(where: { $0.id == entry.id }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    @objc private func editSelected(_ sender: Any?) {
        guard let current = selectedEntry, let (entry, password) = runEditDialog(editing: current) else { return }
        store.update(entry, password: password)
    }

    @objc private func removeSelected(_ sender: Any?) {
        guard let entry = selectedEntry, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the proxy \(entry.address)?"
        alert.informativeText = "Its password is deleted with it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.remove(id: entry.id)
        }
    }

    /// The "Use" checkbox: ticking one proxy puts it in use (and the
    /// others out of use); unticking the one in use turns the proxy off.
    @objc private func useToggled(_ sender: NSButton) {
        guard store.proxies.indices.contains(sender.tag) else { return }
        let id = store.proxies[sender.tag].id
        store.setActive(sender.state == .on ? id : nil)
    }

    @objc private func toolToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = ProxyTool(rawValue: raw) else { return }
        store.setTool(tool, enabled: sender.state == .on)
    }

    // MARK: - Add / edit dialog

    /// Asks for a proxy's address, user name and password, until they are
    /// valid or the user cancels. The returned password is nil when the
    /// stored one should be kept.
    private func runEditDialog(editing current: ProxyEntry?) -> (ProxyEntry, String?)? {
        let fields = EditFields()
        editFields = fields
        defer { editFields = nil }

        fields.url.placeholderString = "socks5://user:password@host:port"
        fields.url.delegate = self
        fields.host.placeholderString = "196.0.2.10"
        fields.port.placeholderString = "1080"
        fields.password.placeholderString = current == nil ? "" : "unchanged"
        fields.remoteDNS.state = (current?.remoteDNS ?? true) ? .on : .off
        if let current {
            fields.host.stringValue = current.host
            fields.port.stringValue = String(current.port)
            fields.user.stringValue = current.username
        }
        for field in [fields.url, fields.host, fields.port, fields.user, fields.password] {
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }

        let grid = NSGridView(views: [
            [label("Paste URL"), fields.url],
            [label("Host"), fields.host],
            [label("Port"), fields.port],
            [label("User"), fields.user],
            [label("Password"), fields.password],
            [NSGridCell.emptyContentView, fields.remoteDNS],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.frame.size = grid.fittingSize

        var problem: String?
        while true {
            let alert = NSAlert()
            alert.messageText = current == nil ? "Add a SOCKS5 Proxy" : "Edit Proxy"
            alert.informativeText = problem ?? "Paste a URL to fill in the fields, or type them."
            alert.accessoryView = grid
            alert.addButton(withTitle: current == nil ? "Add" : "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.sharingType = .none
            alert.window.initialFirstResponder = current == nil ? fields.url : fields.host
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            let host = fields.host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let user = fields.user.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || "/@?#".contains($0) }) else {
                problem = "Enter the proxy's host name or IP address."
                continue
            }
            guard let port = Int(fields.port.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
                problem = "Enter a port between 1 and 65535."
                continue
            }
            var entry = current ?? ProxyEntry(host: host, port: port, username: user)
            entry.host = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
            entry.port = port
            entry.username = user
            entry.remoteDNS = fields.remoteDNS.state == .on
            // No user means no password; an empty password field while
            // editing keeps the stored one.
            let password: String? = user.isEmpty ? "" : (fields.password.stringValue.isEmpty && current != nil ? nil : fields.password.stringValue)
            return (entry, password)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(11)
        return label
    }

    /// A URL pasted (or typed) into the dialog's first field fills in the others.
    func controlTextDidChange(_ obj: Notification) {
        guard let fields = editFields, (obj.object as? NSTextField) === fields.url,
              let (entry, password) = ProxyEntry.parse(fields.url.stringValue) else { return }
        fields.host.stringValue = entry.host
        fields.port.stringValue = String(entry.port)
        fields.user.stringValue = entry.username
        fields.password.stringValue = password
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.proxies.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = store.proxies[row]
        if tableColumn?.identifier == Self.useColumn {
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(useToggled(_:)))
            box.state = entry.id == store.activeID ? .on : .off
            box.tag = row
            return box
        }
        // Never the password, only whether there is one.
        let hasPassword = !(store.password(for: entry.id) ?? "").isEmpty
        var text = entry.url(password: nil)
        if hasPassword { text = text.replacingOccurrences(of: "@", with: ":••••@") }
        let label = NSTextField(labelWithString: text)
        label.font = Theme.mono(11)
        label.textColor = entry.id == store.activeID ? Theme.hot : Theme.muted
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }
}
