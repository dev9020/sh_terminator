import AppKit
import Testing
@testable import SHTerminator

@Suite struct DirectionalFocusTests {
    // Two columns; the right one is split into top and bottom (y-up).
    let left = NSRect(x: 0, y: 0, width: 100, height: 200)
    let rightTop = NSRect(x: 101, y: 101, width: 100, height: 99)
    let rightBottom = NSRect(x: 101, y: 0, width: 100, height: 100)

    @Test func neighboursOnEachSide() {
        #expect(SplitPaneController.directionalScore(from: left, to: rightTop, .right) != nil)
        #expect(SplitPaneController.directionalScore(from: left, to: rightTop, .left) == nil)
        #expect(SplitPaneController.directionalScore(from: rightBottom, to: rightTop, .up) != nil)
        #expect(SplitPaneController.directionalScore(from: rightBottom, to: rightTop, .down) == nil)
        #expect(SplitPaneController.directionalScore(from: rightTop, to: rightBottom, .down) != nil)
    }

    @Test func panesThatDoNotOverlapAcrossTheAxisAreSkipped() {
        // Diagonal: right-top is not "below" the left column's top half.
        let leftTop = NSRect(x: 0, y: 101, width: 100, height: 99)
        #expect(SplitPaneController.directionalScore(from: leftTop, to: rightBottom, .down) == nil)
    }
}

@Suite struct PrivateFileTests {
    @Test @MainActor func writesOwnerOnlyAndReplacesAtomically() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shterminator-tests-\(UUID().uuidString)/nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let file = dir.appendingPathComponent("notes.txt")

        try SecurityHardening.writePrivateFile(Data("one".utf8), to: file)
        try SecurityHardening.writePrivateFile(Data("two".utf8), to: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == "two")
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(dirMode == 0o700)
        // No temp files left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["notes.txt"])
    }

    @Test @MainActor func tightensAnExistingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shterminator-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

        try SecurityHardening.writePrivateFile(Data("x".utf8), to: dir.appendingPathComponent("favorites.json"))

        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
    }
}

@Suite struct RunningProgramsTests {
    @Test func describesOneOrMany() {
        #expect(RunningPrograms.describe(["ssh"]) == "ssh is still running.")
        #expect(RunningPrograms.describe(["ssh", "ssh", "vim"]) == "3 programs are still running (ssh, vim).")
    }
}

@Suite struct NestedSplitSizeTests {
    /// ⌘D then ⌘⇧D (and the other way round): the nested split must get
    /// half the window, not shrink to the width/height of a pane's title,
    /// and a divider moved by hand must stay where it was put.
    @Test(arguments: [(SplitAxis.vertical, SplitAxis.horizontal), (.horizontal, .vertical)])
    @MainActor func nestedSplitKeepsItsShare(first: SplitAxis, second: SplitAxis) throws {
        let controller = SplitPaneController(root: .leaf(PaneSession()))
        defer { controller.root.leaves().forEach { $0.terminate() }; controller.stop() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = controller.containerView

        controller.splitFocused(axis: first)
        controller.splitFocused(axis: second)
        controller.containerView.layoutSubtreeIfNeeded()

        let outer = try #require(controller.containerView.subviews.first as? NSSplitView)
        let length = { (view: NSView) in first == .vertical ? view.frame.width : view.frame.height }
        let total = length(outer)
        for pane in try #require(outer.subviews.last as? NSSplitView).subviews {
            #expect(abs(length(pane) - total / 2) < 2)
        }

        outer.setPosition(total * 0.3, ofDividerAt: 0)
        outer.layoutSubtreeIfNeeded()
        #expect(abs(length(outer.subviews[0]) - total * 0.3) < 2)
    }
}

@Suite struct PaneClickTests {
    /// A click on the top pane focuses the top pane, not the bottom one.
    @Test @MainActor func clickHitsThePaneUnderTheMouse() throws {
        let controller = PaneWindowController(root: PaneTemplates.twoHorizontal())
        defer { controller.splitController.root.leaves().forEach { $0.terminate() }; controller.splitController.stop() }
        let window = try #require(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()

        let split = controller.splitController
        for session in split.root.leaves() {
            let view = try #require(split.containerView.subviews.first?.subviews.first { split.session(containing: $0) === session })
            let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            #expect(controller.session(atWindowLocation: center) === session)
        }
    }
}
