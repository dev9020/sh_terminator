import AppKit

/// Owns one window's pane tree, turns it into a live `NSSplitView` hierarchy,
/// and drives splitting, closing, focus navigation and pane zoom.
@MainActor
final class SplitPaneController: NSObject {
    private(set) var root: PaneNode
    let containerView = NSView()

    private var focused: PaneSession
    private var zoomed: PaneSession?

    /// Fired once the last pane in this window has been closed; the owning
    /// window controller should close the window itself.
    var onEmptied: (() -> Void)?

    init(root: PaneNode) {
        self.root = root
        self.focused = root.leaves().first!
        super.init()
        rebuild()
    }

    var focusedSession: PaneSession { focused }

    // MARK: - Mutating the tree

    func splitFocused(axis: SplitAxis) {
        let newSession = PaneSession()
        let replacement: PaneNode = .split(axis, [.leaf(focused), .leaf(newSession)])
        root = root.replacing(focused, with: replacement)
        if zoomed != nil { zoomed = newSession }
        focused = newSession
        rebuild()
    }

    @discardableResult
    func closeFocused() -> Bool {
        removeSession(focused)
    }

    /// Removes a pane (whether focused or not — also used when its shell
    /// exits on its own). Returns `true` if that was the last pane, in which
    /// case `onEmptied` has already fired.
    @discardableResult
    func removeSession(_ session: PaneSession) -> Bool {
        guard let remaining = root.removing(session) else {
            session.terminate()
            onEmptied?()
            return true
        }
        root = remaining
        session.terminate()
        if zoomed === session { zoomed = nil }
        if focused === session { focused = root.leaves().first! }
        rebuild()
        return false
    }

    func focusNext() { moveFocus(by: 1) }
    func focusPrevious() { moveFocus(by: -1) }

    private func moveFocus(by delta: Int) {
        let leaves = root.leaves()
        guard leaves.count > 1, let index = leaves.firstIndex(where: { $0 === focused }) else { return }
        let next = leaves[(index + delta + leaves.count) % leaves.count]
        focus(next)
    }

    func toggleZoom() {
        zoomed = (zoomed == nil) ? focused : nil
        rebuild()
    }

    func focus(_ session: PaneSession) {
        guard root.contains(session) else { return }
        focused = session
        updateFocusRings()
        containerView.window?.makeFirstResponder(session.terminalView)
    }

    // MARK: - Building the view hierarchy

    private func rebuild() {
        containerView.subviews.forEach { $0.removeFromSuperview() }

        let displayedTree: PaneNode
        if let zoomed, root.contains(zoomed) {
            displayedTree = .leaf(zoomed)
        } else {
            displayedTree = root
        }

        let view = buildView(for: displayedTree)
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        updateFocusRings()
        containerView.window?.makeFirstResponder(focused.terminalView)
    }

    private func buildView(for node: PaneNode) -> NSView {
        switch node {
        case .leaf(let session):
            wireSession(session)
            return session.terminalView
        case .split(let axis, let children):
            let split = EqualSplitView()
            split.isVertical = (axis == .vertical)
            split.dividerStyle = .thin
            for child in children {
                split.addSubview(buildView(for: child))
            }
            return split
        }
    }

    private func wireSession(_ session: PaneSession) {
        session.terminalView.wantsLayer = true
        session.terminalView.layer?.borderWidth = 2
        session.onProcessExit = { [weak self] in self?.removeSession(session) }
    }

    private func updateFocusRings() {
        let visible = zoomed != nil ? [zoomed!] : root.leaves()
        for pane in visible {
            let isFocused = pane === focused
            pane.terminalView.layer?.borderColor = isFocused
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
        }
    }
}
