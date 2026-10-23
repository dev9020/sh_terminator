import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let shared = AppDelegate()

    private var windowControllers: [PaneWindowController] = []
    private var favoritesMenu: FavoritesMenu?
    private lazy var favoritesWindow = FavoritesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SecurityHardening.hardenProcess()
        let favoritesMenu = FavoritesMenu(appDelegate: self)
        self.favoritesMenu = favoritesMenu
        NSApp.mainMenu = MainMenuBuilder.build(appDelegate: self, favoritesMenu: favoritesMenu.menu)
        PrivacyLock.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyLockDidChange(_:)), name: PrivacyLock.didChange, object: nil)
        openWindow(root: PaneTemplates.single())
        // Activation may already have happened before launch finished.
        SecurityHardening.updateSecureKeyboardEntry()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SecurityHardening.updateSecureKeyboardEntry()
        PrivacyLock.shared.appDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) {
        SecurityHardening.updateSecureKeyboardEntry()
        PrivacyLock.shared.appDidResignActive()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = windowControllers.flatMap { $0.runningPrograms() }
        guard !running.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit sh_terminator?"
        alert.informativeText = RunningPrograms.describe(running) + " Quitting will end them."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
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

    @objc private func privacyLockDidChange(_ notification: Notification) {
        if PrivacyLock.shared.isEngaged {
            favoritesWindow.window?.orderOut(nil)
        }
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

    // MARK: - Settings (app menu)

    @objc func toggleSecureKeyboardEntry(_ sender: Any?) {
        AppSettings.secureKeyboardEntry.toggle()
        SecurityHardening.updateSecureKeyboardEntry()
    }

    @objc func lockNow(_ sender: Any?) {
        PrivacyLock.shared.lock()
    }

    /// The menu item's tag is the number of minutes (0 = never).
    @objc func setAutoLockMinutes(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        AppSettings.autoLockMinutes = item.tag
    }

    @objc func toggleHideWhenInactive(_ sender: Any?) {
        AppSettings.hideWhenInactive.toggle()
    }

    @objc func togglePersistNotes(_ sender: Any?) {
        AppSettings.persistNotes.toggle()
        NotesStore.shared.persistenceSettingChanged()
    }

    @objc func increaseFontSize(_ sender: Any?) { changeFontSize(by: 1) }
    @objc func decreaseFontSize(_ sender: Any?) { changeFontSize(by: -1) }

    @objc func resetFontSize(_ sender: Any?) {
        AppSettings.fontSize = 0
        applyFontSizeEverywhere()
    }

    private func changeFontSize(by delta: CGFloat) {
        let current = AppSettings.fontSize > 0 ? AppSettings.fontSize : NSFont.systemFontSize
        AppSettings.fontSize = min(max(current + delta, 8), 36)
        applyFontSizeEverywhere()
    }

    private func applyFontSizeEverywhere() {
        for controller in windowControllers {
            controller.applyFontSize()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSecureKeyboardEntry(_:)):
            menuItem.state = AppSettings.secureKeyboardEntry ? .on : .off
        case #selector(setAutoLockMinutes(_:)):
            menuItem.state = AppSettings.autoLockMinutes == menuItem.tag ? .on : .off
        case #selector(toggleHideWhenInactive(_:)):
            menuItem.state = AppSettings.hideWhenInactive ? .on : .off
        case #selector(togglePersistNotes(_:)):
            menuItem.state = AppSettings.persistNotes ? .on : .off
        case #selector(lockNow(_:)):
            return PrivacyLock.shared.state != .locked
        default:
            // Opening windows or favorites would show content past the lock.
            return !PrivacyLock.shared.isEngaged
        }
        return true
    }
}

/// Names of programs still running in panes, for "are you sure" prompts.
enum RunningPrograms {
    static func describe(_ names: [String]) -> String {
        let unique = Array(NSOrderedSet(array: names)) as! [String]
        let list = unique.count > 3
            ? unique.prefix(3).joined(separator: ", ") + " and \(unique.count - 3) more"
            : unique.joined(separator: ", ")
        return names.count == 1
            ? "\(list) is still running."
            : "\(names.count) programs are still running (\(list))."
    }
}
