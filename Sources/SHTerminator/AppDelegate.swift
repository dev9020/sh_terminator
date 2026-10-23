import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var windowControllers: [PaneWindowController] = []
    private var favoritesMenu: FavoritesMenu?
    private lazy var favoritesWindow = FavoritesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SecurityHardening.hardenProcess()
        let favoritesMenu = FavoritesMenu(appDelegate: self)
        self.favoritesMenu = favoritesMenu
        NSApp.mainMenu = MainMenuBuilder.build(appDelegate: self, favoritesMenu: favoritesMenu.menu)
        openWindow(root: PaneTemplates.single())
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotesStore.shared.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowClosed(_ controller: PaneWindowController) {
        windowControllers.removeAll { $0 === controller }
    }

    private func openWindow(root: PaneNode) {
        let controller = PaneWindowController(root: root)
        windowControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu actions

    @objc func newWindow(_ sender: Any?) {
        openWindow(root: PaneTemplates.single())
    }

    @objc func showFavorites(_ sender: Any?) {
        favoritesWindow.showWindow(nil)
    }

    func showFavorites(addingCommand command: String) {
        favoritesWindow.addAndEdit(command: command)
    }

    @objc func newTemplateTwoVertical(_ sender: Any?) { openWindow(root: PaneTemplates.twoVertical()) }
    @objc func newTemplateTwoHorizontal(_ sender: Any?) { openWindow(root: PaneTemplates.twoHorizontal()) }
    @objc func newTemplateFour(_ sender: Any?) { openWindow(root: PaneTemplates.four()) }
    @objc func newTemplateSix(_ sender: Any?) { openWindow(root: PaneTemplates.six()) }
    @objc func newTemplateEight(_ sender: Any?) { openWindow(root: PaneTemplates.eight()) }
    @objc func newTemplateTen(_ sender: Any?) { openWindow(root: PaneTemplates.ten()) }
}
