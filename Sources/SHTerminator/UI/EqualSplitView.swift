import AppKit

/// An `NSSplitView` that starts with its dividers spaced evenly between
/// however many subviews it was given, then behaves like a normal,
/// freely-draggable split view from that point on.
final class EqualSplitView: ThemedSplitView {
    private var didSetInitialPositions = false

    override func layout() {
        super.layout()
        guard !didSetInitialPositions, subviews.count > 1, bounds.width > 0, bounds.height > 0 else { return }
        didSetInitialPositions = true
        distributeEqually()
    }

    private func distributeEqually() {
        let total = isVertical ? bounds.width : bounds.height
        let count = subviews.count
        guard count > 1, total > 0 else { return }
        let each = total / CGFloat(count)
        var position: CGFloat = 0
        for index in 0..<(count - 1) {
            position += each
            setPosition(position, ofDividerAt: index)
        }
    }
}
