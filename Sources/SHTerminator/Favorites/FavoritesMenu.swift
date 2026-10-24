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

        let store = FavoritesStore.shared
        if store.items.isEmpty {
            let empty = NSMenuItem(title: "No Favorites Yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        // Once there are categories, each non-empty one gets a heading and
        // its favorites are indented under it. Shortcuts follow display order.
        let showsHeadings = !store.categories.isEmpty
        var index = 0
        for section in store.sections where !section.favorites.isEmpty {
            if showsHeadings {
                menu.addItem(Self.heading(section.name))
            }
            for favorite in section.favorites {
                let key = index < 9 ? String(index + 1) : ""
                let item = NSMenuItem(title: favorite.name, action: #selector(PaneWindowController.insertFavorite(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = [.command]
                item.representedObject = favorite.id
                item.indentationLevel = showsHeadings ? 1 : 0
                // No tooltip with the command: tooltips (like menus) are
                // separate windows that screenshots and screen sharing capture.
                menu.addItem(item)
                index += 1
            }
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

    private static func heading(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return .sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
