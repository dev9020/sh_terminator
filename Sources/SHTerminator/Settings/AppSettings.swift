import AppKit

/// The few user preferences this app has, kept in the standard defaults
/// (`~/Library/Preferences/dev.local.shterminator.plist`). Only switches
/// and numbers live here — never terminal content, commands or notes.
@MainActor
enum AppSettings {
    /// Posted after any setting below changes.
    static let didChange = Notification.Name("AppSettingsDidChange")

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let secureKeyboardEntry = "secureKeyboardEntry"
        static let autoLockMinutes = "autoLockMinutes"
        static let hideWhenInactive = "hideWhenInactive"
        static let lockOnSleep = "lockOnSleep"
        static let paneTitleInWindowTitle = "paneTitleInWindowTitle"
        static let persistNotes = "persistNotes"
        static let fontSize = "fontSize"
        static let showLauncher = "showLauncher"
        static let showShortcutsBar = "showShortcutsBar"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.secureKeyboardEntry: true,
            Key.autoLockMinutes: 0,
            Key.hideWhenInactive: false,
            Key.lockOnSleep: true,
            Key.paneTitleInWindowTitle: false,
            Key.persistNotes: true,
            Key.fontSize: 0.0,
            Key.showLauncher: true,
            Key.showShortcutsBar: true,
        ])
    }

    /// Keystrokes typed into this app can't be seen by other processes'
    /// event taps (see `SecurityHardening.updateSecureKeyboardEntry`).
    static var secureKeyboardEntry: Bool {
        get { defaults.bool(forKey: Key.secureKeyboardEntry) }
        set { set(newValue, for: Key.secureKeyboardEntry) }
    }

    /// Lock every window after this many minutes without input; 0 = never.
    static var autoLockMinutes: Int {
        get { defaults.integer(forKey: Key.autoLockMinutes) }
        set { set(newValue, for: Key.autoLockMinutes) }
    }

    /// Cover every window while another app is frontmost.
    static var hideWhenInactive: Bool {
        get { defaults.bool(forKey: Key.hideWhenInactive) }
        set { set(newValue, for: Key.hideWhenInactive) }
    }

    /// Lock every window when the Mac sleeps, its screens sleep, the screen
    /// is locked or the user switches to another account.
    static var lockOnSleep: Bool {
        get { defaults.bool(forKey: Key.lockOnSleep) }
        set { set(newValue, for: Key.lockOnSleep) }
    }

    /// Show the focused pane's title (which the program in it may set, e.g.
    /// to the command line being run) as the window title. Off by default:
    /// unlike the window's content, its title is visible outside it — in the
    /// Dock menu, Mission Control, to Accessibility clients and in other
    /// apps' window lists.
    static var paneTitleInWindowTitle: Bool {
        get { defaults.bool(forKey: Key.paneTitleInWindowTitle) }
        set { set(newValue, for: Key.paneTitleInWindowTitle) }
    }

    /// Keep the Notes text on disk across restarts (otherwise memory only).
    static var persistNotes: Bool {
        get { defaults.bool(forKey: Key.persistNotes) }
        set { set(newValue, for: Key.persistNotes) }
    }

    /// Terminal font size in points; 0 = SwiftTerm's default.
    static var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.fontSize)) }
        set { set(Double(newValue), for: Key.fontSize) }
    }

    /// Start with the `Launcher` (boot screen + layout choice) instead of
    /// opening a single-pane window straight away.
    static var showLauncher: Bool {
        get { defaults.bool(forKey: Key.showLauncher) }
        set { set(newValue, for: Key.showLauncher) }
    }

    /// Show the `ShortcutsBar` along the bottom of every terminal window.
    static var showShortcutsBar: Bool {
        get { defaults.bool(forKey: Key.showShortcutsBar) }
        set { set(newValue, for: Key.showShortcutsBar) }
    }

    private static func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
