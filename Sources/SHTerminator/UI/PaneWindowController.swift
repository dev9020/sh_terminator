import AppKit

/// One window = one pane tree. Window-scoped actions (split, close pane,
/// focus navigation, zoom) are implemented here and reached through the
/// responder chain, which we explicitly extend to include this controller.
final class PaneWindowController: NSWindowController, NSWindowDelegate {
    let splitController: SplitPaneController
    private var clickMonitor: Any?

    init(root: PaneNode) {
        self.splitController = SplitPaneController(root: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "sh_terminator"
        window.contentView = splitController.containerView
        window.center()

        super.init(window: window)

        window.delegate = self
        // Explicitly insert this controller into the responder chain so the
        // window-scoped menu actions below (target: nil) reach it.
        window.nextResponder = self

        SecurityHardening.harden(window: window)

        splitController.onEmptied = { [weak self] in
            self?.close()
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

    @objc func copyAndClearClipboard(_ sender: Any?) {
        SecurityHardening.copyAndScheduleClipboardClear(from: splitController.focusedSession.terminalView)
    }
}
