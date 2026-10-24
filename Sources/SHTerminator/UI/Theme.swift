import AppKit

/// The red-on-black HUD look shared by the launcher, the terminal windows,
/// their panes, the favorites and the notes.
@MainActor
enum Theme {
    static let red = NSColor(srgbRed: 1, green: 0.13, blue: 0.08, alpha: 1)
    static let dimRed = red.withAlphaComponent(0.45)
    static let faintRed = red.withAlphaComponent(0.18)
    /// Secondary text and icons in the working UI (commands, inactive
    /// headers, toolbar buttons): lighter than `red` and opaque, so it stays
    /// readable on the dark background. `dimRed` is for decoration only.
    static let muted = NSColor(srgbRed: 1, green: 0.55, blue: 0.5, alpha: 1)
    /// Near-white with a red cast, for what must stand out (statuses, the
    /// selected item).
    static let hot = NSColor(srgbRed: 1, green: 0.86, blue: 0.8, alpha: 1)
    static let background = NSColor(srgbRed: 0.035, green: 0, blue: 0, alpha: 1)
    /// A shade above `background`, for headers and the sidebar.
    static let panel = NSColor(srgbRed: 0.07, green: 0.012, blue: 0.01, alpha: 1)
    /// The terminal's default text: readable for long sessions, still red.
    static let terminalText = NSColor(srgbRed: 1, green: 0.8, blue: 0.74, alpha: 1)
    static let selection = red.withAlphaComponent(0.35)

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Dark controls, alerts and menus everywhere in the app.
    static func applyToApp() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    static func style(window: NSWindow) {
        window.backgroundColor = background
        window.titlebarAppearsTransparent = true
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
