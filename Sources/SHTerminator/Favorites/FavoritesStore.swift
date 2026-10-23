import Foundation

struct Favorite: Codable, Equatable {
    var id = UUID()
    var name: String
    var command: String
}

/// Saved commands the user can insert (never run) into the focused pane.
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

    private(set) var items: [Favorite] = []

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SHTerminator", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }()

    private init() {
        load()
    }

    func favorite(id: UUID) -> Favorite? {
        items.first { $0.id == id }
    }

    @discardableResult
    func add(name: String, command: String) -> Favorite {
        let favorite = Favorite(name: name, command: command)
        items.append(favorite)
        save()
        return favorite
    }

    func update(_ favorite: Favorite) {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }), items[index] != favorite else { return }
        items[index] = favorite
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source) else { return }
        let favorite = items.remove(at: source)
        items.insert(favorite, at: min(destination, items.count))
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([Favorite].self, from: data)
        } catch {
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
            try SecurityHardening.writePrivateFile(encoder.encode(items), to: fileURL)
        } catch {
            NSLog("sh_terminator: failed to save favorites: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: FavoritesStore.didChange, object: self)
    }
}
