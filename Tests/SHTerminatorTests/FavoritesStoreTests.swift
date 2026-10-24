import Foundation
import Testing
@testable import SHTerminator

@MainActor
@Suite struct FavoritesStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shterminator-tests-\(UUID().uuidString)")
    var file: URL { dir.appendingPathComponent("favorites.json") }

    @Test func readsTheOldArrayFormatIntoTheBuiltInGroup() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"[{"id":"\#(UUID().uuidString)","name":"DB","command":"psql"}]"#.utf8).write(to: file)

        let store = FavoritesStore(fileURL: file)
        #expect(store.items.map(\.name) == ["DB"])
        #expect(store.sections.map(\.name) == ["Uncategorized"])
        #expect(store.sections[0].favorites.map(\.name) == ["DB"])
    }

    @Test func categoriesSurviveARestart() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FavoritesStore(fileURL: file)
        let servers = store.addCategory(name: "Servers")
        store.add(name: "Bastion", command: "ssh bastion", categoryID: servers.id)
        store.renameCategory(nil, to: "General")

        let reloaded = FavoritesStore(fileURL: file)
        #expect(reloaded.sections.map(\.name) == ["General", "Servers"])
        #expect(reloaded.favorites(in: servers.id).map(\.name) == ["Bastion"])
    }

    @Test func blankNamesAreRefused() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FavoritesStore(fileURL: file)
        store.renameCategory(nil, to: "   ")
        #expect(store.uncategorizedName == "Uncategorized")
    }

    @Test func deletingACategoryKeepsItsFavorites() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FavoritesStore(fileURL: file)
        let servers = store.addCategory(name: "Servers")
        store.add(name: "Bastion", command: "ssh bastion", categoryID: servers.id)
        store.removeCategory(servers.id)
        #expect(store.categories.isEmpty)
        #expect(store.favorites(in: nil).map(\.name) == ["Bastion"])
    }

    /// ⌘1…⌘9 follow what the sidebar shows: grouped by category.
    @Test func displayOrderIsGroupedByCategory() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FavoritesStore(fileURL: file)
        let servers = store.addCategory(name: "Servers")
        store.add(name: "a", command: "", categoryID: servers.id)
        store.add(name: "b", command: "")
        store.add(name: "c", command: "", categoryID: servers.id)
        store.add(name: "d", command: "")
        #expect(store.ordered.map(\.name) == ["b", "d", "a", "c"])
    }

    @Test func movesWithinItsCategory() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FavoritesStore(fileURL: file)
        let servers = store.addCategory(name: "Servers")
        let a = store.add(name: "a", command: "", categoryID: servers.id)
        store.add(name: "x", command: "")
        store.add(name: "b", command: "", categoryID: servers.id)
        store.add(name: "c", command: "", categoryID: servers.id)

        store.move(id: a.id, to: 2)
        #expect(store.favorites(in: servers.id).map(\.name) == ["b", "c", "a"])
        store.move(id: a.id, to: 0)
        #expect(store.favorites(in: servers.id).map(\.name) == ["a", "b", "c"])
        #expect(store.favorites(in: nil).map(\.name) == ["x"])
    }
}
