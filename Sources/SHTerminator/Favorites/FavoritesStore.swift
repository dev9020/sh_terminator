import Foundation

struct Favorite: Codable, Equatable {
    var id = UUID()
    var name: String
    var command: String
    /// `nil` puts it in the built-in "Uncategorized" group (as do older
    /// files, which have no such key).
    var categoryID: UUID?
}

struct FavoriteCategory: Codable, Equatable {
    var id = UUID()
    var name: String
}

/// One group of favorites as the sidebar, menu and manager show it.
struct FavoriteSection {
    /// `nil` for the built-in "Uncategorized" group.
    let categoryID: UUID?
    let name: String
    let favorites: [Favorite]
}

/// Saved commands the user can insert (never run) into the focused pane,
/// grouped into categories. Every favorite belongs to one: a user-made one,
/// or the built-in group that can be renamed but not deleted.
///
/// Persisted as plain JSON at
/// `~/Library/Application Support/SHTerminator/favorites.json`, readable only
/// by the current user (dir 0700, file 0600). This is the one thing the app
/// writes to disk on purpose — see SECURITY.md for why secrets should still
/// not be stored inline in a favorite.
@MainActor
final class FavoritesStore {
    static let shared = FavoritesStore()
    static let didChange = Notification.Name("FavoritesStoreDidChange")
    static let defaultUncategorizedName = "Uncategorized"

    /// Every favorite; within a category, this order is the display order.
    private(set) var items: [Favorite] = []
    /// User-made categories, in display order (after the built-in group).
    private(set) var categories: [FavoriteCategory] = []
    private(set) var uncategorizedName = FavoritesStore.defaultUncategorizedName

    private let fileURL: URL

    /// On disk. Older versions wrote a bare `[Favorite]` array, still read.
    private struct File: Codable {
        var uncategorizedName: String
        var categories: [FavoriteCategory]
        var favorites: [Favorite]
    }

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SHTerminator", isDirectory: true)
        .appendingPathComponent("favorites.json")) {
        self.fileURL = fileURL
        load()
    }

    func favorite(id: UUID) -> Favorite? {
        items.first { $0.id == id }
    }

    /// The built-in group first, then the user's categories — empty ones too.
    var sections: [FavoriteSection] {
        [FavoriteSection(categoryID: nil, name: uncategorizedName, favorites: favorites(in: nil))]
            + categories.map { FavoriteSection(categoryID: $0.id, name: $0.name, favorites: favorites(in: $0.id)) }
    }

    /// All favorites in display order; the first nine get ⌘1…⌘9.
    var ordered: [Favorite] {
        sections.flatMap(\.favorites)
    }

    func favorites(in categoryID: UUID?) -> [Favorite] {
        items.filter { $0.categoryID == categoryID }
    }

    func categoryName(_ categoryID: UUID?) -> String {
        categories.first { $0.id == categoryID }?.name ?? uncategorizedName
    }

    // MARK: - Favorites

    @discardableResult
    func add(name: String, command: String, categoryID: UUID? = nil) -> Favorite {
        let favorite = Favorite(name: name, command: command, categoryID: knownCategory(categoryID))
        items.append(favorite)
        save()
        return favorite
    }

    func update(_ favorite: Favorite) {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }) else { return }
        var favorite = favorite
        favorite.categoryID = knownCategory(favorite.categoryID)
        guard items[index] != favorite else { return }
        items[index] = favorite
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Moves a favorite to `position` among the favorites of its own
    /// category (counted without it).
    func move(id: UUID, to position: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let favorite = items.remove(at: index)
        let siblings = items.indices.filter { items[$0].categoryID == favorite.categoryID }
        let position = max(position, 0)
        let target = position < siblings.count ? siblings[position] : (siblings.last.map { $0 + 1 } ?? items.count)
        items.insert(favorite, at: target)
        save()
    }

    // MARK: - Categories

    @discardableResult
    func addCategory(name: String) -> FavoriteCategory {
        let category = FavoriteCategory(name: name)
        categories.append(category)
        save()
        return category
    }

    /// `nil` renames the built-in group. A blank name is ignored.
    func renameCategory(_ categoryID: UUID?, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let categoryID {
            guard let index = categories.firstIndex(where: { $0.id == categoryID }), categories[index].name != name else { return }
            categories[index].name = name
        } else {
            guard uncategorizedName != name else { return }
            uncategorizedName = name
        }
        save()
    }

    /// Its favorites are kept and move to the built-in group.
    func removeCategory(_ categoryID: UUID) {
        categories.removeAll { $0.id == categoryID }
        for index in items.indices where items[index].categoryID == categoryID {
            items[index].categoryID = nil
        }
        save()
    }

    func moveCategory(from source: Int, to destination: Int) {
        guard categories.indices.contains(source) else { return }
        let category = categories.remove(at: source)
        categories.insert(category, at: min(max(destination, 0), categories.count))
        save()
    }

    /// A category that no longer exists means the built-in group.
    private func knownCategory(_ categoryID: UUID?) -> UUID? {
        categories.contains { $0.id == categoryID } ? categoryID : nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(File.self, from: data) {
            categories = file.categories
            uncategorizedName = file.uncategorizedName.isEmpty ? Self.defaultUncategorizedName : file.uncategorizedName
            items = file.favorites.map { favorite in
                var favorite = favorite
                favorite.categoryID = knownCategory(favorite.categoryID)
                return favorite
            }
        } else if let legacy = try? decoder.decode([Favorite].self, from: data) {
            items = legacy.map { favorite in
                var favorite = favorite
                favorite.categoryID = nil
                return favorite
            }
        } else {
            // Keep the unreadable file aside instead of silently overwriting
            // the user's commands on the next save.
            let backup = fileURL.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = File(uncategorizedName: uncategorizedName, categories: categories, favorites: items)
            try SecurityHardening.writePrivateFile(encoder.encode(file), to: fileURL)
        } catch {
            NSLog("sh_terminator: failed to save favorites: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: FavoritesStore.didChange, object: self)
    }
}
