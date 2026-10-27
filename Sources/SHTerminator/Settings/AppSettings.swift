import AppKit

/// The few user preferences this app has, kept in the standard defaults
/// (`~/Library/Preferences/dev.local.shterminator.plist`). Only switches
/// and numbers live here — never terminal content, commands or notes.
///
/// Any process of this user can change that file (`defaults write`) or
/// launch the app with arguments that override it (`-secureKeyboardEntry
/// NO`). So launch arguments are ignored, the file is read once at launch
/// — a running app can't be weakened behind its back — and protections that
/// are off are shown in every window (`weakenedProtections`).
@MainActor
enum AppSettings {
    /// Posted after any setting below changes.
    static let didChange = Notification.Name("AppSettingsDidChange")

    /// The app's two looks. Dark is what every window opens with the very
    /// first time the app runs; the user can switch to light from the menu,
    /// and that choice sticks across restarts.
    enum ColorScheme: String {
        case dark, light
    }

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
        static let colorScheme = "colorScheme"
    }

    /// Every setting as read at launch, then as changed in the app.
    private static var values: [String: Any] = [:]

    static func registerDefaults() {
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
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
            Key.colorScheme: ColorScheme.dark.rawValue,
        ])
        for key in [Key.secureKeyboardEntry, Key.hideWhenInactive, Key.lockOnSleep, Key.paneTitleInWindowTitle, Key.persistNotes, Key.showLauncher, Key.showShortcutsBar] {
            values[key] = defaults.bool(forKey: key)
        }
        values[Key.autoLockMinutes] = defaults.integer(forKey: Key.autoLockMinutes)
        values[Key.fontSize] = defaults.double(forKey: Key.fontSize)
        values[Key.colorScheme] = defaults.string(forKey: Key.colorScheme)
    }

    /// Keystrokes typed into this app can't be seen by other processes'
    /// event taps (see `SecurityHardening.updateSecureKeyboardEntry`).
    static var secureKeyboardEntry: Bool {
        get { bool(Key.secureKeyboardEntry) }
        set { set(newValue, for: Key.secureKeyboardEntry) }
    }

    /// Lock every window after this many minutes without input; 0 = never.
    static var autoLockMinutes: Int {
        get { integer(Key.autoLockMinutes) }
        set { set(newValue, for: Key.autoLockMinutes) }
    }

    /// Cover every window while another app is frontmost.
    static var hideWhenInactive: Bool {
        get { bool(Key.hideWhenInactive) }
        set { set(newValue, for: Key.hideWhenInactive) }
    }

    /// Lock every window when the Mac sleeps, its screens sleep, the screen
    /// is locked or the user switches to another account.
    static var lockOnSleep: Bool {
        get { bool(Key.lockOnSleep) }
        set { set(newValue, for: Key.lockOnSleep) }
    }

    /// Show the focused pane's title (which the program in it may set, e.g.
    /// to the command line being run) as the window title. Off by default:
    /// unlike the window's content, its title is visible outside it — in the
    /// Dock menu, Mission Control, to Accessibility clients and in other
    /// apps' window lists.
    static var paneTitleInWindowTitle: Bool {
        get { bool(Key.paneTitleInWindowTitle) }
        set { set(newValue, for: Key.paneTitleInWindowTitle) }
    }

    /// Keep the Notes text on disk across restarts (otherwise memory only).
    static var persistNotes: Bool {
        get { bool(Key.persistNotes) }
        set { set(newValue, for: Key.persistNotes) }
    }

    /// Terminal font size in points; 0 = SwiftTerm's default.
    static var fontSize: CGFloat {
        get { CGFloat(values[Key.fontSize] as? Double ?? 0) }
        set { set(Double(newValue), for: Key.fontSize) }
    }

    /// Start with the `Launcher` (boot screen + layout choice) instead of
    /// opening a single-pane window straight away.
    static var showLauncher: Bool {
        get { bool(Key.showLauncher) }
        set { set(newValue, for: Key.showLauncher) }
    }

    /// Show the `ShortcutsBar` along the bottom of every terminal window.
    static var showShortcutsBar: Bool {
        get { bool(Key.showShortcutsBar) }
        set { set(newValue, for: Key.showShortcutsBar) }
    }

    /// Dark or light look for every window. Dark the first time the app
    /// ever runs; whatever the user picks afterwards persists.
    static var colorScheme: ColorScheme {
        get { ColorScheme(rawValue: values[Key.colorScheme] as? String ?? "") ?? .dark }
        set { set(newValue.rawValue, for: Key.colorScheme) }
    }

    /// Protections set weaker than their defaults, as short labels for the
    /// window (see `ShortcutsBar`); empty when none are.
    static var weakenedProtections: [String] {
        weakenedProtections(secureKeyboardEntry: secureKeyboardEntry, lockOnSleep: lockOnSleep, paneTitleInWindowTitle: paneTitleInWindowTitle)
    }

    nonisolated static func weakenedProtections(secureKeyboardEntry: Bool, lockOnSleep: Bool, paneTitleInWindowTitle: Bool) -> [String] {
        var weakened: [String] = []
        if !secureKeyboardEntry { weakened.append("SECURE KEYBOARD ENTRY OFF") }
        if !lockOnSleep { weakened.append("NO LOCK ON SLEEP") }
        if paneTitleInWindowTitle { weakened.append("PANE TITLE IN WINDOW TITLE") }
        return weakened
    }

    private static func bool(_ key: String) -> Bool {
        values[key] as? Bool ?? false
    }

    private static func integer(_ key: String) -> Int {
        values[key] as? Int ?? 0
    }

    private static func set(_ value: Any, for key: String) {
        values[key] = value
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
