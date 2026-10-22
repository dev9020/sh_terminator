import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var windowControllers: [PaneWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        SecurityHardening.hardenProcess()
        NSApp.mainMenu = MainMenuBuilder.build(appDelegate: self)
        openWindow(root: PaneTemplates.single())
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

    @objc func newTemplateTwoVertical(_ sender: Any?) { openWindow(root: PaneTemplates.twoVertical()) }
    @objc func newTemplateTwoHorizontal(_ sender: Any?) { openWindow(root: PaneTemplates.twoHorizontal()) }
    @objc func newTemplateFour(_ sender: Any?) { openWindow(root: PaneTemplates.four()) }
    @objc func newTemplateSix(_ sender: Any?) { openWindow(root: PaneTemplates.six()) }
    @objc func newTemplateEight(_ sender: Any?) { openWindow(root: PaneTemplates.eight()) }
    @objc func newTemplateTen(_ sender: Any?) { openWindow(root: PaneTemplates.ten()) }
}
