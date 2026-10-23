import AppKit

/// Builds the whole menu bar in code — no Storyboard/XIB, so there is
/// nothing there but what is written here. Window-scoped items (split,
/// close pane, focus, zoom, secure copy) leave `target` nil and are routed
/// through the responder chain to the key window's `PaneWindowController`.
/// Window-creation items target `AppDelegate.shared` directly since they are
/// not tied to any particular existing window.
enum MainMenuBuilder {
    static func build(appDelegate: AppDelegate, favoritesMenu: NSMenu) -> NSMenu {
        let main = NSMenu()

        main.addItem(appMenuItem(appDelegate: appDelegate))
        main.addItem(fileMenuItem(appDelegate: appDelegate))
        main.addItem(editMenuItem())
        main.addItem(viewMenuItem(appDelegate: appDelegate))
        main.addItem(paneMenuItem())

        let favoritesItem = NSMenuItem()
        favoritesItem.submenu = favoritesMenu
        main.addItem(favoritesItem)

        return main
    }

    private static func item(_ title: String, _ selector: Selector?, _ key: String, modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        return menuItem
    }

    private static func appMenuItem(appDelegate: AppDelegate) -> NSMenuItem {
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: nil))
        appMenu.addItem(.separator())

        // Security settings; checkmarks are set in AppDelegate.validateMenuItem.
        appMenu.addItem(item("Secure Keyboard Entry", #selector(AppDelegate.toggleSecureKeyboardEntry(_:)), "", target: appDelegate))
        appMenu.addItem(item("Lock Now", #selector(AppDelegate.lockNow(_:)), "l", modifiers: [.command, .control], target: appDelegate))
        let autoLockMenu = NSMenu(title: "Auto-Lock")
        for (title, minutes) in [("Never", 0), ("After 1 Minute", 1), ("After 5 Minutes", 5), ("After 15 Minutes", 15), ("After 30 Minutes", 30)] {
            let entry = item(title, #selector(AppDelegate.setAutoLockMinutes(_:)), "", target: appDelegate)
            entry.tag = minutes
            autoLockMenu.addItem(entry)
        }
        let autoLockItem = NSMenuItem(title: "Auto-Lock", action: nil, keyEquivalent: "")
        autoLockItem.submenu = autoLockMenu
        appMenu.addItem(autoLockItem)
        appMenu.addItem(item("Lock When Mac Sleeps or Screen Locks", #selector(AppDelegate.toggleLockOnSleep(_:)), "", target: appDelegate))
        appMenu.addItem(item("Hide Windows When in Background", #selector(AppDelegate.toggleHideWhenInactive(_:)), "", target: appDelegate))
        appMenu.addItem(item("Show Pane Title in Window Title", #selector(AppDelegate.togglePaneTitleInWindowTitle(_:)), "", target: appDelegate))
        appMenu.addItem(item("Keep Notes Across Restarts", #selector(AppDelegate.togglePersistNotes(_:)), "", target: appDelegate))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))

        let menuItem = NSMenuItem()
        menuItem.submenu = appMenu
        return menuItem
    }

    private static func fileMenuItem(appDelegate: AppDelegate) -> NSMenuItem {
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n", target: appDelegate))

        let templateMenu = NSMenu(title: "New Window From Template")
        let templateItem = NSMenuItem(title: "New Window From Template", action: nil, keyEquivalent: "")
        templateItem.submenu = templateMenu
        templateMenu.addItem(item("2 Panes — Side by Side", #selector(AppDelegate.newTemplateTwoVertical(_:)), "", target: appDelegate))
        templateMenu.addItem(item("2 Panes — Stacked", #selector(AppDelegate.newTemplateTwoHorizontal(_:)), "", target: appDelegate))
        templateMenu.addItem(item("4 Panes", #selector(AppDelegate.newTemplateFour(_:)), "", target: appDelegate))
        templateMenu.addItem(item("6 Panes", #selector(AppDelegate.newTemplateSix(_:)), "", target: appDelegate))
        templateMenu.addItem(item("8 Panes", #selector(AppDelegate.newTemplateEight(_:)), "", target: appDelegate))
        templateMenu.addItem(item("10 Panes", #selector(AppDelegate.newTemplateTen(_:)), "", target: appDelegate))
        fileMenu.addItem(templateItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Pane", #selector(PaneWindowController.closeFocusedPane(_:)), "w"))
        fileMenu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", modifiers: [.command, .shift]))

        let menuItem = NSMenuItem()
        menuItem.submenu = fileMenu
        return menuItem
    }

    private static func editMenuItem() -> NSMenuItem {
        let editMenu = NSMenu(title: "Edit")
        // Undo/Redo/Cut only apply to text fields (notes, favorites editor);
        // they show as disabled while a terminal pane has focus.
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Copy & Clear Clipboard After 20s", #selector(PaneWindowController.copyAndClearClipboard(_:)), "c", modifiers: [.command, .option]))
        editMenu.addItem(item("Clear Scrollback", #selector(PaneWindowController.clearScrollback(_:)), "k"))
        editMenu.addItem(.separator())

        // Handled by SwiftTerm's own find bar in the focused pane; the tags
        // are the standard NSFindPanelAction values it switches on.
        let findMenu = NSMenu(title: "Find")
        for (title, key, modifiers, action) in [
            ("Find…", "f", NSEvent.ModifierFlags.command, NSFindPanelAction.showFindPanel),
            ("Find Next", "g", .command, .next),
            ("Find Previous", "g", [.command, .shift], .previous),
        ] {
            let entry = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers: modifiers)
            entry.tag = Int(action.rawValue)
            findMenu.addItem(entry)
        }
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = findMenu
        editMenu.addItem(findItem)

        let menuItem = NSMenuItem()
        menuItem.submenu = editMenu
        return menuItem
    }

    private static func viewMenuItem(appDelegate: AppDelegate) -> NSMenuItem {
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Bigger", #selector(AppDelegate.increaseFontSize(_:)), "+", target: appDelegate))
        // ⌘= is the same key as ⌘+ without Shift; accept both.
        let biggerAlias = item("Bigger", #selector(AppDelegate.increaseFontSize(_:)), "=", target: appDelegate)
        biggerAlias.isHidden = true
        biggerAlias.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(biggerAlias)
        viewMenu.addItem(item("Smaller", #selector(AppDelegate.decreaseFontSize(_:)), "-", target: appDelegate))
        viewMenu.addItem(item("Default Font Size", #selector(AppDelegate.resetFontSize(_:)), "0", target: appDelegate))

        let menuItem = NSMenuItem()
        menuItem.submenu = viewMenu
        return menuItem
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(key)!))
    }

    private static func paneMenuItem() -> NSMenuItem {
        let paneMenu = NSMenu(title: "Pane")
        paneMenu.addItem(item("Split Vertically", #selector(PaneWindowController.splitPaneVertically(_:)), "d"))
        paneMenu.addItem(item("Split Horizontally", #selector(PaneWindowController.splitPaneHorizontally(_:)), "d", modifiers: [.command, .shift]))
        paneMenu.addItem(.separator())
        paneMenu.addItem(item("Focus Next Pane", #selector(PaneWindowController.focusNextPane(_:)), "]"))
        paneMenu.addItem(item("Focus Previous Pane", #selector(PaneWindowController.focusPreviousPane(_:)), "["))
        paneMenu.addItem(item("Focus Pane on the Left", #selector(PaneWindowController.focusPaneLeft(_:)), arrow(NSLeftArrowFunctionKey), modifiers: [.command, .option]))
        paneMenu.addItem(item("Focus Pane on the Right", #selector(PaneWindowController.focusPaneRight(_:)), arrow(NSRightArrowFunctionKey), modifiers: [.command, .option]))
        paneMenu.addItem(item("Focus Pane Above", #selector(PaneWindowController.focusPaneAbove(_:)), arrow(NSUpArrowFunctionKey), modifiers: [.command, .option]))
        paneMenu.addItem(item("Focus Pane Below", #selector(PaneWindowController.focusPaneBelow(_:)), arrow(NSDownArrowFunctionKey), modifiers: [.command, .option]))
        paneMenu.addItem(.separator())
        paneMenu.addItem(item("Toggle Zoom Pane", #selector(PaneWindowController.toggleZoomPane(_:)), "\r"))
        paneMenu.addItem(item("Broadcast Input to All Panes", #selector(PaneWindowController.toggleBroadcastInput(_:)), "i", modifiers: [.command, .option]))

        let menuItem = NSMenuItem()
        menuItem.submenu = paneMenu
        return menuItem
    }
}
