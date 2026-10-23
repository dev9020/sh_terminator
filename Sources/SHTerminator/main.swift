import AppKit

// Before anything can read a setting (activation callbacks may arrive
// ahead of applicationDidFinishLaunching).
MainActor.assumeIsolated { AppSettings.registerDefaults() }

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
