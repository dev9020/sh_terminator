import AppKit

MainActor.assumeIsolated {
    // First of all: no core dump of this process, ever.
    SecurityHardening.hardenProcess()
    // Before anything can read a setting (activation callbacks may arrive
    // ahead of applicationDidFinishLaunching).
    AppSettings.registerDefaults()
}

// A pane's zsh asking for the proxy in use: answer and exit, no app.
if CommandLine.arguments.dropFirst().first == PaneProxyQuery.argument {
    exit(MainActor.assumeIsolated { PaneProxyQuery.run() })
}

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
