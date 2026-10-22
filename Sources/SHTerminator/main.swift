import AppKit

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
