import Foundation

/// Ready-made pane layouts for "New Window From Template". Each call spawns
/// brand-new `PaneSession`s (new shell processes) — templates are only used
/// to seed a fresh window, never to re-layout an existing one.
@MainActor
enum PaneTemplates {
    /// A grid of `rows` x `cols` freshly-started panes.
    static func grid(rows: Int, cols: Int) -> PaneNode {
        precondition(rows >= 1 && cols >= 1)
        let rowNodes: [PaneNode] = (0..<rows).map { _ in
            let cells: [PaneNode] = (0..<cols).map { _ in .leaf(PaneSession()) }
            return cells.count == 1 ? cells[0] : .split(.vertical, cells)
        }
        return rowNodes.count == 1 ? rowNodes[0] : .split(.horizontal, rowNodes)
    }

    static func single() -> PaneNode { .leaf(PaneSession()) }
    static func twoVertical() -> PaneNode { grid(rows: 1, cols: 2) }
    static func twoHorizontal() -> PaneNode { grid(rows: 2, cols: 1) }
    static func four() -> PaneNode { grid(rows: 2, cols: 2) }
    static func six() -> PaneNode { grid(rows: 2, cols: 3) }
    static func eight() -> PaneNode { grid(rows: 2, cols: 4) }
    static func ten() -> PaneNode { grid(rows: 2, cols: 5) }
}
