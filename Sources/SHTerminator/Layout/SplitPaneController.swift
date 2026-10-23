import AppKit

enum FocusDirection {
    case left, right, up, down
}

/// Owns one window's pane tree, turns it into a live `NSSplitView` hierarchy,
/// and drives splitting, closing, focus navigation, pane zoom and input
/// broadcast.
@MainActor
final class SplitPaneController: NSObject {
    private(set) var root: PaneNode
    let containerView = NSView()

    private var focused: PaneSession
    private var zoomed: PaneSession?
    private var paneViews: [UUID: PaneContainerView] = [:]
    private var headerTimer: Timer?

    /// When on, whatever is typed or pasted into one pane of this window is
    /// sent to every other pane of it too.
    private(set) var isBroadcasting = false
    private var isRelayingBroadcast = false

    /// Fired once the last pane in this window has been closed; the owning
    /// window controller should close the window itself.
    var onEmptied: (() -> Void)?

    /// Fired whenever the focused pane's header text may have changed.
    var onFocusedTitleChange: ((String) -> Void)?

    init(root: PaneNode) {
        self.root = root
        self.focused = root.leaves().first!
        super.init()
        rebuild()
        // Program names and directories have no change notification; a
        // cheap poll keeps the headers current.
        headerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePaneHeaders() }
        }
    }

    var focusedSession: PaneSession { focused }

    func stop() {
        headerTimer?.invalidate()
        headerTimer = nil
    }

    /// The pane `view` belongs to (its terminal, header or frame), if any.
    func session(containing view: NSView) -> PaneSession? {
        root.leaves().first { session in
            guard let paneView = paneViews[session.id] else { return false }
            return view === paneView || view.isDescendant(of: paneView)
        }
    }

    // MARK: - Mutating the tree

    /// The new pane's shell starts in the focused pane's current directory.
    func splitFocused(axis: SplitAxis) {
        let newSession = PaneSession(currentDirectory: focused.currentDirectory)
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
        paneViews[session.id] = nil
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

    /// Moves focus to the nearest pane on that side of the focused one, by
    /// on-screen geometry (so it works however the splits are nested).
    func focus(_ direction: FocusDirection) {
        guard zoomed == nil, let current = frame(of: focused) else { return }
        let candidates = root.leaves().compactMap { session -> (PaneSession, NSRect)? in
            guard session !== focused, let frame = frame(of: session) else { return nil }
            return (session, frame)
        }
        let best = candidates
            .compactMap { session, frame -> (PaneSession, CGFloat, CGFloat)? in
                guard let score = Self.directionalScore(from: current, to: frame, direction) else { return nil }
                return (session, score.distance, score.offset)
            }
            .min { ($0.1, $0.2) < ($1.1, $1.2) }
        if let best { focus(best.0) }
    }

    /// How far `candidate` is from `current` in `direction` (gap between
    /// edges, then distance between centres across that axis), or nil if it
    /// isn't on that side or doesn't overlap it across the axis at all.
    /// Frames are y-up (AppKit's default), so "up" means larger y.
    nonisolated static func directionalScore(from current: NSRect, to candidate: NSRect, _ direction: FocusDirection) -> (distance: CGFloat, offset: CGFloat)? {
        let slack: CGFloat = 4
        switch direction {
        case .left, .right:
            let gap = direction == .left ? current.minX - candidate.maxX : candidate.minX - current.maxX
            guard gap > -slack, candidate.maxY > current.minY + slack, candidate.minY < current.maxY - slack else { return nil }
            return (max(gap, 0), abs(candidate.midY - current.midY))
        case .up, .down:
            let gap = direction == .up ? candidate.minY - current.maxY : current.minY - candidate.maxY
            guard gap > -slack, candidate.maxX > current.minX + slack, candidate.minX < current.maxX - slack else { return nil }
            return (max(gap, 0), abs(candidate.midX - current.midX))
        }
    }

    /// In `containerView`'s (unflipped, y-up) coordinates.
    private func frame(of session: PaneSession) -> NSRect? {
        guard let view = paneViews[session.id], view.superview != nil else { return nil }
        return view.convert(view.bounds, to: containerView)
    }

    func toggleZoom() {
        zoomed = (zoomed == nil) ? focused : nil
        rebuild()
    }

    func focus(_ session: PaneSession) {
        guard root.contains(session) else { return }
        focused = session
        updatePaneHeaders()
        containerView.window?.makeFirstResponder(session.terminalView)
    }

    func applyFontSize() {
        for session in root.leaves() {
            session.applyFontSize()
        }
    }

    // MARK: - Broadcast

    func toggleBroadcast() {
        isBroadcasting.toggle()
        updatePaneHeaders()
    }

    private func relay(_ input: UserInput, from source: PaneSession) {
        guard isBroadcasting, !isRelayingBroadcast else { return }
        isRelayingBroadcast = true
        defer { isRelayingBroadcast = false }
        for session in root.leaves() where session !== source {
            switch input {
            case .bytes(let data):
                session.terminalView.send(data: data)
            case .paste(let text):
                session.terminalView.sendPaste(text)
            }
        }
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

        updatePaneHeaders()
        containerView.window?.makeFirstResponder(focused.terminalView)
    }

    private func buildView(for node: PaneNode) -> NSView {
        switch node {
        case .leaf(let session):
            return paneView(for: session)
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

    private func paneView(for session: PaneSession) -> PaneContainerView {
        if let existing = paneViews[session.id] {
            existing.removeFromSuperview()
            existing.translatesAutoresizingMaskIntoConstraints = true
            return existing
        }
        let view = PaneContainerView(session: session)
        paneViews[session.id] = view
        session.onProcessExit = { [weak self] in self?.removeSession(session) }
        session.onTitleChange = { [weak self] in self?.updatePaneHeaders() }
        session.terminalView.onUserInput = { [weak self, weak session] input in
            guard let self, let session else { return }
            self.relay(input, from: session)
        }
        return view
    }

    private func updatePaneHeaders() {
        for session in root.leaves() {
            paneViews[session.id]?.update(title: Self.title(for: session), focused: session === focused, broadcasting: isBroadcasting)
        }
        onFocusedTitleChange?(Self.title(for: focused))
    }

    /// The program's own title if it set one, else "program — directory".
    private static func title(for session: PaneSession) -> String {
        if let title = session.programTitle { return title }
        let program = session.displayProgramName
        guard let directory = session.currentDirectory else { return program }
        return "\(program) — \((directory as NSString).abbreviatingWithTildeInPath)"
    }
}
