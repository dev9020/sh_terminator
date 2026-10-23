import AppKit

/// The "Favorites" menu: one item per saved command (⌘1…⌘9 for the first
/// nine), rebuilt whenever the store changes. Insert items leave `target` nil
/// so they reach the key window's `PaneWindowController` via the responder chain.
@MainActor
final class FavoritesMenu: NSObject {
    let menu = NSMenu(title: "Favorites")
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange(_:)), name: FavoritesStore.didChange, object: nil)
    }

    @objc private func storeDidChange(_ notification: Notification) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        let favorites = FavoritesStore.shared.items
        if favorites.isEmpty {
            let empty = NSMenuItem(title: "No Favorites Yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, favorite) in favorites.enumerated() {
            let key = index < 9 ? String(index + 1) : ""
            let item = NSMenuItem(title: favorite.name, action: #selector(PaneWindowController.insertFavorite(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command]
            item.representedObject = favorite.id
            item.toolTip = favorite.command
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let toggleSidebar = NSMenuItem(title: "Toggle Favorites Sidebar", action: #selector(PaneWindowController.toggleFavoritesSidebar(_:)), keyEquivalent: "b")
        toggleSidebar.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggleSidebar)
        let addSelection = NSMenuItem(title: "Add Selection to Favorites", action: #selector(PaneWindowController.addSelectionToFavorites(_:)), keyEquivalent: "s")
        addSelection.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(addSelection)
        let manage = NSMenuItem(title: "Manage Favorites…", action: #selector(AppDelegate.showFavorites(_:)), keyEquivalent: "f")
        manage.keyEquivalentModifierMask = [.command, .shift]
        manage.target = appDelegate
        menu.addItem(manage)
    }
}
