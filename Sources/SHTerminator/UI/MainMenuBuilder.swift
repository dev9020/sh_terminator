import AppKit

/// Builds the whole menu bar in code — no Storyboard/XIB, so there is
/// nothing there but what is written here. Window-scoped items (split,
/// close pane, focus, zoom, secure copy) leave `target` nil and are routed
/// through the responder chain to the key window's `PaneWindowController`.
/// Window-creation items target `AppDelegate.shared` directly since they are
/// not tied to any particular existing window.
enum MainMenuBuilder {
    static func build(appDelegate: AppDelegate) -> NSMenu {
        let main = NSMenu()

        main.addItem(appMenuItem())
        main.addItem(fileMenuItem(appDelegate: appDelegate))
        main.addItem(editMenuItem())
        main.addItem(paneMenuItem())

        return main
    }

    private static func item(_ title: String, _ selector: Selector?, _ key: String, modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        return menuItem
    }

    private static func appMenuItem() -> NSMenuItem {
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: nil))
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
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Copy & Clear Clipboard After 20s", #selector(PaneWindowController.copyAndClearClipboard(_:)), "c", modifiers: [.command, .option]))

        let menuItem = NSMenuItem()
        menuItem.submenu = editMenu
        return menuItem
    }

    private static func paneMenuItem() -> NSMenuItem {
        let paneMenu = NSMenu(title: "Pane")
        paneMenu.addItem(item("Split Vertically", #selector(PaneWindowController.splitPaneVertically(_:)), "d"))
        paneMenu.addItem(item("Split Horizontally", #selector(PaneWindowController.splitPaneHorizontally(_:)), "d", modifiers: [.command, .shift]))
        paneMenu.addItem(.separator())
        paneMenu.addItem(item("Focus Next Pane", #selector(PaneWindowController.focusNextPane(_:)), "]"))
        paneMenu.addItem(item("Focus Previous Pane", #selector(PaneWindowController.focusPreviousPane(_:)), "["))
        paneMenu.addItem(.separator())
        paneMenu.addItem(item("Toggle Zoom Pane", #selector(PaneWindowController.toggleZoomPane(_:)), "\r"))

        let menuItem = NSMenuItem()
        menuItem.submenu = paneMenu
        return menuItem
    }
}
