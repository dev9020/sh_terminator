import Foundation
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
