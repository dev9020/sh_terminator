import AppKit

/// The red-on-black (or red-on-white) HUD look shared by the launcher, the
/// terminal windows, their panes, the favorites and the notes.
///
/// Every color below is a computed property, not a constant: it switches on
/// `AppSettings.colorScheme` so the whole app can change look without a
/// restart. Views that cache a color (as a `CALayer.backgroundColor`, say)
/// need to re-read it and reassign after a change — see each view's
/// `applyTheme()`.
@MainActor
enum Theme {
    static var red: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 1, green: 0.13, blue: 0.08, alpha: 1)
        case .light: return NSColor(srgbRed: 0.72, green: 0.07, blue: 0.02, alpha: 1)
        }
    }

    static var dimRed: NSColor { red.withAlphaComponent(AppSettings.colorScheme == .dark ? 0.45 : 0.55) }
    static var faintRed: NSColor { red.withAlphaComponent(AppSettings.colorScheme == .dark ? 0.18 : 0.25) }

    /// Secondary text and icons in the working UI (commands, inactive
    /// headers, toolbar buttons): lighter than `red` and opaque, so it stays
    /// readable on the background. `dimRed` is for decoration only.
    static var muted: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 1, green: 0.55, blue: 0.5, alpha: 1)
        case .light: return NSColor(srgbRed: 0.5, green: 0.2, blue: 0.15, alpha: 1)
        }
    }

    /// What must stand out (statuses, the selected item): near-white with a
    /// red cast in the dark theme, near-black with a red cast in the light
    /// one — always the strongest contrast against `background`.
    static var hot: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 1, green: 0.86, blue: 0.8, alpha: 1)
        case .light: return NSColor(srgbRed: 0.25, green: 0.02, blue: 0, alpha: 1)
        }
    }

    static var background: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 0.035, green: 0, blue: 0, alpha: 1)
        case .light: return NSColor(srgbRed: 0.98, green: 0.965, blue: 0.96, alpha: 1)
        }
    }

    /// A shade above `background`, for headers and the sidebar.
    static var panel: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 0.07, green: 0.012, blue: 0.01, alpha: 1)
        case .light: return NSColor(srgbRed: 0.93, green: 0.9, blue: 0.89, alpha: 1)
        }
    }

    /// The terminal's default text: readable for long sessions, still red.
    static var terminalText: NSColor {
        switch AppSettings.colorScheme {
        case .dark: return NSColor(srgbRed: 1, green: 0.8, blue: 0.74, alpha: 1)
        case .light: return NSColor(srgbRed: 0.22, green: 0.05, blue: 0.03, alpha: 1)
        }
    }

    static var selection: NSColor { red.withAlphaComponent(AppSettings.colorScheme == .dark ? 0.35 : 0.25) }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Matches the app's chrome (controls, alerts, menus) to the current
    /// theme. Call again after `AppSettings.colorScheme` changes.
    static func applyToApp() {
        NSApp.appearance = NSAppearance(named: AppSettings.colorScheme == .dark ? .darkAqua : .aqua)
    }

    static func style(window: NSWindow) {
        window.backgroundColor = background
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: AppSettings.colorScheme == .dark ? .darkAqua : .aqua)
    }

    static func style(terminal: TerminalPaneView) {
        terminal.nativeBackgroundColor = background
        terminal.nativeForegroundColor = terminalText
        terminal.caretColor = red
        terminal.selectedTextBackgroundColor = selection
    }

    /// A section title such as "// FAVORITES".
    static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: "// " + text)
        label.font = mono(10, .bold)
        label.textColor = red
        return label
    }

    static func iconButton(_ symbol: String, _ description: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description)!, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = red
        button.refusesFirstResponder = true
        return button
    }
}

/// An `NSSplitView` whose dividers are thin red lines, whatever the
/// orientation (the stock thin divider is barely visible on a dark
/// background, and horizontal ones don't show at all).
class ThemedSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.faintRed }

    override func drawDivider(in rect: NSRect) {
        dividerColor.setFill()
        rect.fill()
    }
}

extension NSView {
    /// Marks this view and every descendant dirty, so views with custom
    /// drawing that depends on `Theme` (a split view's divider, a table
    /// row's selection) redraw in the new colors after a theme change.
    func forceRedisplayTree() {
        needsDisplay = true
        for subview in subviews { subview.forceRedisplayTree() }
    }
}

/// A table row that draws its selection in the theme's red and no
/// background of its own (not even for group rows).
final class ThemedRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 4, dy: 1)
        Theme.red.withAlphaComponent(0.16).setFill()
        rect.fill()
        Theme.red.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height).fill()
    }
}
