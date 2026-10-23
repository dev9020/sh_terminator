import AppKit

MainActor.assumeIsolated {
    // First of all: no core dump of this process, ever.
    SecurityHardening.hardenProcess()
    // Before anything can read a setting (activation callbacks may arrive
    // ahead of applicationDidFinishLaunching).
    AppSettings.registerDefaults()
}

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
