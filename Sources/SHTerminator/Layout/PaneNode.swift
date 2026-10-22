import Foundation

/// `.vertical`  — divider is vertical, panes sit side by side (left | right).
/// `.horizontal` — divider is horizontal, panes are stacked (top / bottom).
enum SplitAxis {
    case horizontal
    case vertical
}

/// A tree describing how a window's panes are arranged, identical in shape
/// to the layout trees tmux/iTerm2 use internally. A leaf is one running
/// `PaneSession`; a split is an axis plus its children in display order.
indirect enum PaneNode {
    case leaf(PaneSession)
    case split(SplitAxis, [PaneNode])

    /// All panes in this subtree, in left-to-right / top-to-bottom order.
    func leaves() -> [PaneSession] {
        switch self {
        case .leaf(let session):
            return [session]
        case .split(_, let children):
            return children.flatMap { $0.leaves() }
        }
    }

    func contains(_ session: PaneSession) -> Bool {
        leaves().contains { $0 === session }
    }

    /// New tree with the `target` leaf replaced by `replacement`.
    func replacing(_ target: PaneSession, with replacement: PaneNode) -> PaneNode {
        switch self {
        case .leaf(let session):
            return session === target ? replacement : self
        case .split(let axis, let children):
            return .split(axis, children.map { $0.replacing(target, with: replacement) })
        }
    }

    /// New tree with the `target` leaf removed. A split that would be left
    /// with a single child collapses into that child. Returns `nil` if
    /// removing `target` would leave the tree empty.
    func removing(_ target: PaneSession) -> PaneNode? {
        switch self {
        case .leaf(let session):
            return session === target ? nil : self
        case .split(let axis, let children):
            let remaining = children.compactMap { $0.removing(target) }
            if remaining.isEmpty { return nil }
            if remaining.count == 1 { return remaining[0] }
            return .split(axis, remaining)
        }
    }
}
