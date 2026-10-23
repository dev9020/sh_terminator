import AppKit

/// One window = one pane tree. Window-scoped actions (split, close pane,
/// focus navigation, zoom) are implemented here and reached through the
/// responder chain, which we explicitly extend to include this controller.
final class PaneWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate {
    let splitController: SplitPaneController
    private let favoritesSidebar = FavoritesSidebar()
    private let sidebarSplit = NSSplitView()
    private var clickMonitor: Any?

    private static let sidebarWidth: CGFloat = 130

    init(root: PaneNode) {
        self.splitController = SplitPaneController(root: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080 + Self.sidebarWidth, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "sh_terminator"
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
        window.contentView = sidebarSplit
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func handleClick(_ event: NSEvent) {
        guard event.window === window, let contentView = window?.contentView else { return }
        let location = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(location) else { return }
        for session in splitController.root.leaves() where hitView === session.terminalView || hitView.isDescendant(of: session.terminalView) {
            splitController.focus(session)
            break
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

    func windowWillClose(_ notification: Notification) {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        for pane in splitController.root.leaves() {
            pane.terminate()
        }
        AppDelegate.shared.windowClosed(self)
    }

    // MARK: - Pane actions (routed via the responder chain)

    @objc func splitPaneVertically(_ sender: Any?) {
        splitController.splitFocused(axis: .vertical)
    }

    @objc func splitPaneHorizontally(_ sender: Any?) {
        splitController.splitFocused(axis: .horizontal)
    }

    @objc func closeFocusedPane(_ sender: Any?) {
        splitController.closeFocused()
    }

    @objc func focusNextPane(_ sender: Any?) {
        splitController.focusNext()
    }

    @objc func focusPreviousPane(_ sender: Any?) {
        splitController.focusPrevious()
    }

    @objc func toggleZoomPane(_ sender: Any?) {
        splitController.toggleZoom()
    }

    // MARK: - Favorites

    func insert(command: String) {
        let session = splitController.focusedSession
        session.insertWithoutRunning(command)
        splitController.focus(session)
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
        SecurityHardening.copyAndScheduleClipboardClear(from: splitController.focusedSession.terminalView)
    }
}
