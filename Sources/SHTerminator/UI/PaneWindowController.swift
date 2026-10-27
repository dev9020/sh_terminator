import AppKit

/// One window = one pane tree. Window-scoped actions (split, close pane,
/// focus navigation, zoom) are implemented here and reached through the
/// responder chain, which we explicitly extend to include this controller.
final class PaneWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    let splitController: SplitPaneController
    private let favoritesSidebar = FavoritesSidebar()
    private let sidebarSplit = ThemedSplitView()
    /// Holds `sidebarSplit` above the shortcuts bar.
    private let content: WindowContentView
    private let lockScreen = LockScreenView()
    private var clickMonitor: Any?
    /// Set once the user agreed to close despite running programs, so the
    /// second `windowShouldClose` lets it through.
    private var closeConfirmed = false
    /// The focused pane's header text, for `updateWindowTitle`.
    private var focusedPaneTitle = ""

    private static let sidebarWidth: CGFloat = 260
    private static let baseTitle = "sh_terminator"

    init(root: PaneNode) {
        self.splitController = SplitPaneController(root: root)
        self.content = WindowContentView(main: sidebarSplit)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080 + Self.sidebarWidth, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.baseTitle
        Theme.style(window: window)
        // Panes on the left, the favorites sidebar (one per window, shared by
        // all panes) on the right. The sidebar holds its width when the window
        // resizes. Both holding priorities must stay below the divider-drag
        // priority (~490), or the user can't drag the divider at all.
        sidebarSplit.isVertical = true
        sidebarSplit.dividerStyle = .thin
        sidebarSplit.addArrangedSubview(splitController.containerView)
        sidebarSplit.addArrangedSubview(favoritesSidebar.view)
        sidebarSplit.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        sidebarSplit.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)
        window.contentView = content
        content.updateShortcutsBar()
        sidebarSplit.layoutSubtreeIfNeeded()
        sidebarSplit.setPosition(sidebarSplit.bounds.width - Self.sidebarWidth, ofDividerAt: 0)
        window.center()

        super.init(window: window)

        window.delegate = self
        sidebarSplit.delegate = self
        // Explicitly insert this controller into the responder chain so the
        // window-scoped menu actions below (target: nil) reach it.
        window.nextResponder = self

        SecurityHardening.harden(window: window)

        splitController.onEmptied = { [weak self] in
            self?.close()
        }
        splitController.onFocusedTitleChange = { [weak self] title in
            self?.focusedPaneTitle = title
            self?.updateWindowTitle()
        }
        favoritesSidebar.onPick = { [weak self] favorite in
            self?.insert(command: favorite.command)
        }

        // SwiftTerm's own `becomeFirstResponder` override isn't `open`, so we
        // can't subclass to observe focus changes — instead we watch clicks
        // ourselves and tell the split controller which pane was hit, purely
        // for updating the focus ring and keyboard-navigation state. The
        // event itself is passed through untouched so normal click-to-type
        // focusing still happens exactly as AppKit would do it anyway.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleClick(event)
            return event
        }

        NotificationCenter.default.addObserver(self, selector: #selector(privacyLockDidChange(_:)), name: PrivacyLock.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)), name: AppSettings.didChange, object: nil)
        privacyLockDidChange(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func handleClick(_ event: NSEvent) {
        guard event.window === window, !PrivacyLock.shared.isEngaged, let session = session(atWindowLocation: event.locationInWindow) else { return }
        splitController.focus(session)
    }

    /// The pane under a point in window coordinates. `hitTest` takes a point
    /// in the *superview's* coordinates: the panes sit in (flipped) split
    /// views, so converting into its own space would mirror y and hit
    /// the bottom pane for a click on the top one.
    func session(atWindowLocation location: NSPoint) -> PaneSession? {
        guard let contentView = window?.contentView, let frameView = contentView.superview,
              let hitView = contentView.hitTest(frameView.convert(location, from: nil)) else { return nil }
        return splitController.session(containing: hitView)
    }

    /// Names of the programs (other than the shells themselves) still
    /// running in this window's panes.
    func runningPrograms() -> [String] {
        splitController.root.leaves().compactMap(\.foregroundProgramName)
    }

    func applyFontSize() {
        splitController.applyFontSize()
    }

    /// Re-applies every `Theme` color in this window: the window background,
    /// every pane and its terminal, the favorites sidebar (with the notes
    /// and connection panel inside it), the shortcuts bar, and the lock
    /// screen.
    func applyTheme() {
        guard let window else { return }
        Theme.style(window: window)
        splitController.applyTheme()
        favoritesSidebar.applyTheme()
        content.applyTheme()
        lockScreen.applyTheme()
        window.contentView?.forceRedisplayTree()
    }

    /// The window title is visible outside the window (Dock menu, Mission
    /// Control, Accessibility, other apps' window lists), so it repeats the
    /// pane's title only if the user asked for that, and never while locked.
    private func updateWindowTitle() {
        let showPane = AppSettings.paneTitleInWindowTitle && !PrivacyLock.shared.isEngaged && !focusedPaneTitle.isEmpty
        window?.title = showPane ? focusedPaneTitle : Self.baseTitle
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        updateWindowTitle()
        content.updateShortcutsBar()
        applyTheme()
    }

    // MARK: - Privacy lock

    /// While locked or covered, the panes and sidebar are taken out of the
    /// window entirely — nothing typed, clicked or sent from a menu can reach
    /// a shell — and put back when it lifts. A sheet still open on the window
    /// (paste check, placeholders, close confirmation) would stay on top of
    /// the lock screen showing its text and taking Return, so it is
    /// cancelled.
    @objc private func privacyLockDidChange(_ notification: Notification?) {
        guard let window else { return }
        let lock = PrivacyLock.shared
        updateWindowTitle()
        if lock.isEngaged {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
            lockScreen.update(for: lock.state)
            if window.contentView !== lockScreen {
                window.contentView = lockScreen
            }
            window.makeFirstResponder(lockScreen)
        } else if window.contentView !== content {
            window.contentView = content
            splitController.focus(splitController.focusedSession)
        }
    }

    // MARK: - NSSplitViewDelegate

    /// The thin divider is 1pt wide; give it a few points of grab area so it
    /// is easy to hit with the mouse.
    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        proposedEffectiveRect.insetBy(dx: -3, dy: 0)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        if let window { SecurityHardening.harden(window: window) }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window { SecurityHardening.harden(window: window) }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if let window { SecurityHardening.harden(window: window) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let running = runningPrograms()
        guard !closeConfirmed, !running.isEmpty else { return true }
        confirm(
            message: "Close this window?",
            info: RunningPrograms.describe(running) + " Closing the window will end them.",
            button: "Close"
        ) { [weak self] in
            self?.closeConfirmed = true
            self?.window?.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        splitController.stop()
        for pane in splitController.root.leaves() {
            pane.terminate()
        }
        AppDelegate.shared.windowClosed(self)
    }

    /// Asks as a sheet on this window; `onConfirm` runs only for `button`.
    private func confirm(message: String, info: String, button: String, onConfirm: @escaping () -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }

    // MARK: - Pane actions (routed via the responder chain)

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleBroadcastInput(_:)) {
            menuItem.state = splitController.isBroadcasting ? .on : .off
        }
        return !PrivacyLock.shared.isEngaged
    }

    @objc func splitPaneVertically(_ sender: Any?) {
        splitController.splitFocused(axis: .vertical)
    }

    @objc func splitPaneHorizontally(_ sender: Any?) {
        splitController.splitFocused(axis: .horizontal)
    }

    @objc func closeFocusedPane(_ sender: Any?) {
        guard let program = splitController.focusedSession.foregroundProgramName else {
            splitController.closeFocused()
            return
        }
        confirm(
            message: "Close this pane?",
            info: "\(program) is still running in it. Closing the pane will end it.",
            button: "Close"
        ) { [weak self] in
            self?.splitController.closeFocused()
        }
    }

    @objc func focusNextPane(_ sender: Any?) {
        splitController.focusNext()
    }

    @objc func focusPreviousPane(_ sender: Any?) {
        splitController.focusPrevious()
    }

    @objc func focusPaneLeft(_ sender: Any?) { splitController.focus(.left) }
    @objc func focusPaneRight(_ sender: Any?) { splitController.focus(.right) }
    @objc func focusPaneAbove(_ sender: Any?) { splitController.focus(.up) }
    @objc func focusPaneBelow(_ sender: Any?) { splitController.focus(.down) }

    @objc func toggleZoomPane(_ sender: Any?) {
        splitController.toggleZoom()
    }

    @objc func toggleBroadcastInput(_ sender: Any?) {
        splitController.toggleBroadcast()
    }

    @objc func clearScrollback(_ sender: Any?) {
        splitController.focusedSession.clearScrollback()
    }

    // MARK: - Favorites

    /// Inserts `command` (after asking for any `{{placeholders}}` in it)
    /// into the pane that was focused when it was picked.
    func insert(command: String) {
        guard let window else { return }
        let session = splitController.focusedSession
        Placeholders.resolve(command, in: window) { [weak self] filled in
            guard let self, self.splitController.root.contains(session), !PrivacyLock.shared.isEngaged else { return }
            session.insertWithoutRunning(filled)
            self.splitController.focus(session)
        }
    }

    @objc func insertFavorite(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let favorite = FavoritesStore.shared.favorite(id: id) else { return }
        insert(command: favorite.command)
    }

    @objc func toggleFavoritesSidebar(_ sender: Any?) {
        let sidebar = favoritesSidebar.view
        sidebar.isHidden.toggle()
        if !sidebar.isHidden {
            sidebarSplit.adjustSubviews()
            sidebarSplit.setPosition(sidebarSplit.bounds.width - Self.sidebarWidth, ofDividerAt: 0)
        }
        splitController.focus(splitController.focusedSession)
    }

    @objc func addSelectionToFavorites(_ sender: Any?) {
        let selection = splitController.focusedSession.terminalView.getSelection() ?? ""
        AppDelegate.shared.showFavorites(addingCommand: selection.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc func copyAndClearClipboard(_ sender: Any?) {
        let selection = splitController.focusedSession.terminalView.getSelection() ?? ""
        SecurityHardening.copySecret(selection, clearAfter: 20)
    }
}
