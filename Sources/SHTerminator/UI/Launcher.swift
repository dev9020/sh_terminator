import AppKit
import QuartzCore

/// The layouts the launcher offers for the first window.
enum LaunchLayout: CaseIterable {
    case single, dual, quad

    var title: String {
        switch self {
        case .single: "SINGLE"
        case .dual: "DUAL"
        case .quad: "QUAD"
        }
    }

    var detail: String {
        switch self {
        case .single: "1 PANE"
        case .dual: "2 PANES · SIDE BY SIDE"
        case .quad: "4 PANES · 2×2 GRID"
        }
    }

    /// The key that picks it straight away.
    var key: String {
        switch self {
        case .single: "1"
        case .dual: "2"
        case .quad: "4"
        }
    }

    var grid: (rows: Int, cols: Int) {
        switch self {
        case .single: (1, 1)
        case .dual: (1, 2)
        case .quad: (2, 2)
        }
    }

    @MainActor
    func makeRoot() -> PaneNode {
        PaneTemplates.grid(rows: grid.rows, cols: grid.cols)
    }
}

/// The startup launcher: a red Terminator-style HUD types out a boot log,
/// then offers the layouts for the first window. A key or click skips the
/// boot log; ←/→ and Return, a number key or a click picks a layout.
/// "Show Launcher at Startup" in the app menu turns it off. It only ever
/// shows fixed text and the app's own settings, never anything from a pane.
@MainActor
final class Launcher {
    /// Keeps the launcher alive while it is on screen.
    private static var current: Launcher?

    private let window: LauncherWindow
    private let onChoose: (LaunchLayout) -> Void

    static func show(onChoose: @escaping (LaunchLayout) -> Void) {
        let launcher = Launcher(onChoose: onChoose)
        current = launcher
        launcher.window.center()
        launcher.window.makeKeyAndOrderFront(nil)
        launcher.window.makeFirstResponder(launcher.window.contentView)
    }

    private init(onChoose: @escaping (LaunchLayout) -> Void) {
        self.onChoose = onChoose
        let view = LauncherView(frame: NSRect(origin: .zero, size: LauncherView.size))
        window = LauncherWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.contentView = view
        SecurityHardening.harden(window: window)
        view.onChoose = { [weak self] layout in self?.dismiss(with: layout) }
    }

    private func dismiss(with layout: LaunchLayout) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.window.orderOut(nil)
                self.onChoose(layout)
                Self.current = nil
            }
        })
    }
}

/// Borderless windows can't become key by default; this one must, to take
/// the keyboard.
private final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class LauncherView: NSView {
    static let size = NSSize(width: 720, height: 500)

    var onChoose: ((LaunchLayout) -> Void)?

    private let reticleCenter = CGPoint(x: 180, y: 330)
    private let logLabel = NSTextField(wrappingLabelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let selectLabel = Theme.sectionLabel("SELECT DEPLOYMENT MODE")
    private let progressFill = CALayer()
    private var cards: [LaunchCard] = []

    private let script = LauncherView.makeScript()
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var timer: Timer?
    private var revealed = 0
    private var pauseTicks = 0
    private var ticks = 0
    /// Ticks since the boot log finished, for the cards' staggered entrance.
    private var readyTicks = 0
    private var selected = 0
    private var chosen = false

    private var booted: Bool { revealed >= script.length }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = Theme.red.withAlphaComponent(0.35).cgColor

        let hud = NSView(frame: bounds)
        hud.wantsLayer = true
        addSubview(hud)
        buildReticle(in: hud.layer!)
        buildCornerBrackets(in: hud.layer!)
        buildProgressBar(in: hud.layer!)
        buildLabels()
        buildCards()

        let overlay = PassthroughView(frame: bounds)
        overlay.wantsLayer = true
        addSubview(overlay)
        buildScanlines(in: overlay.layer!)

        if reduceMotion {
            revealed = script.length
        }
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Boot log

    private static func makeScript() -> NSAttributedString {
        let checks: [(String, String)] = [
            ("CORE DUMPS", "DISABLED"),
            ("SCREEN CAPTURE", "BLOCKED"),
            ("SECURE KEYBOARD", AppSettings.secureKeyboardEntry ? "ENGAGED" : "OFF"),
            ("PRIVACY LOCK", "ARMED"),
            ("NETWORK STACK", "ABSENT"),
            ("PTY SUBSYSTEM", "ONLINE"),
        ]
        let dim: [NSAttributedString.Key: Any] = [.font: Theme.mono(12), .foregroundColor: Theme.dimRed]
        let bright: [NSAttributedString.Key: Any] = [.font: Theme.mono(12), .foregroundColor: Theme.red]
        let hot: [NSAttributedString.Key: Any] = [.font: Theme.mono(12, .bold), .foregroundColor: Theme.hot]

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "SH_TERMINATOR OS v1.0 // NEURAL NET CPU\n\n", attributes: bright))
        for (name, status) in checks {
            let dots = String(repeating: ".", count: max(2, 20 - name.count))
            text.append(NSAttributedString(string: "> \(name) ", attributes: bright))
            text.append(NSAttributedString(string: dots, attributes: dim))
            text.append(NSAttributedString(string: " [\(status)]\n", attributes: hot))
        }
        text.append(NSAttributedString(string: "\nMISSION: PROTECT SECRETS\n", attributes: bright))
        text.append(NSAttributedString(string: "HASTA LA VISTA, KEYLOGGERS.\n", attributes: dim))
        text.append(NSAttributedString(string: "SYSTEM READY. AWAITING ORDERS ", attributes: hot))
        return text
    }

    private func tick() {
        ticks += 1
        if !booted {
            if pauseTicks > 0 {
                pauseTicks -= 1
            } else {
                let next = min(script.length, revealed + 4)
                let chunk = (script.string as NSString).substring(with: NSRange(location: revealed, length: next - revealed))
                revealed = next
                // A short beat at each line end, like a real boot log.
                if chunk.contains("\n") { pauseTicks = 5 }
            }
        } else {
            readyTicks += 1
            revealCards()
        }
        render()
    }

    private func render() {
        let shown = NSMutableAttributedString(attributedString: script.attributedSubstring(from: NSRange(location: 0, length: revealed)))
        let cursorOn = !booted || (ticks / 15) % 2 == 0
        shown.append(NSAttributedString(string: "█", attributes: [
            .font: Theme.mono(12),
            .foregroundColor: cursorOn ? Theme.red : .clear,
        ]))
        logLabel.attributedStringValue = shown

        let progress = CGFloat(revealed) / CGFloat(max(script.length, 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressFill.frame.size.width = (Self.size.width - 160) * progress
        CATransaction.commit()
        percentLabel.stringValue = String(format: "%03d%%", Int(progress * 100))
        hintLabel.stringValue = booted
            ? "← → SELECT · ↩ DEPLOY · 1 2 4 QUICK LAUNCH"
            : "PRESS ANY KEY TO SKIP BOOT"
    }

    /// Fades the section title and then the cards in, one after another.
    private func revealCards() {
        let steps = [selectLabel] + cards as [NSView]
        for (index, view) in steps.enumerated() where view.alphaValue == 0 && readyTicks >= index * 5 {
            if reduceMotion {
                view.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    view.animator().alphaValue = 1
                }
            }
        }
    }

    private func skipBoot() {
        revealed = script.length
        readyTicks = max(readyTicks, 15)
        revealCards()
        render()
    }

    // MARK: - Choosing

    private func select(_ index: Int) {
        selected = (index + cards.count) % cards.count
        for (i, card) in cards.enumerated() {
            card.isHighlighted = i == selected
        }
    }

    private func choose(_ index: Int) {
        guard !chosen else { return }
        guard booted else { return skipBoot() }
        chosen = true
        select(index)
        cards[index].flash()
        onChoose?(cards[index].layout)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if !booted { skipBoot() }
    }

    override func keyDown(with event: NSEvent) {
        guard booted else { return skipBoot() }
        switch event.keyCode {
        case 123: select(selected - 1)  // ←
        case 124: select(selected + 1)  // →
        case 36, 76, 49: choose(selected)  // Return, Enter, Space
        default:
            if let index = LaunchLayout.allCases.firstIndex(where: { $0.key == event.charactersIgnoringModifiers }) {
                choose(index)
            }
        }
    }

    // MARK: - Building

    private func buildCards() {
        let width: CGFloat = 200, gap: CGFloat = 20
        for (index, layout) in LaunchLayout.allCases.enumerated() {
            let card = LaunchCard(layout: layout, frame: NSRect(x: 40 + CGFloat(index) * (width + gap), y: 36, width: width, height: 104))
            card.alphaValue = reduceMotion ? 1 : 0
            card.onHover = { [weak self] in
                guard let self, self.booted, !self.chosen else { return }
                self.select(index)
            }
            card.onClick = { [weak self] in self?.choose(index) }
            addSubview(card)
            cards.append(card)
        }
        select(0)
    }

    private func buildReticle(in root: CALayer) {
        func ring(radius: CGFloat, width: CGFloat, color: NSColor, dash: [NSNumber]? = nil) -> CAShapeLayer {
            let ring = CAShapeLayer()
            ring.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            ring.position = reticleCenter
            ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = width
            ring.lineDashPattern = dash
            root.addSublayer(ring)
            return ring
        }
        func spin(_ layer: CALayer, seconds: CFTimeInterval, clockwise: Bool) {
            guard !reduceMotion else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.byValue = clockwise ? -2 * Double.pi : 2 * Double.pi
            spin.duration = seconds
            spin.repeatCount = .infinity
            layer.add(spin, forKey: "spin")
        }

        spin(ring(radius: 96, width: 1.5, color: Theme.dimRed, dash: [16, 7]), seconds: 9, clockwise: true)
        spin(ring(radius: 76, width: 3, color: Theme.red.withAlphaComponent(0.8), dash: [44, 20]), seconds: 5, clockwise: false)
        _ = ring(radius: 52, width: 1, color: Theme.dimRed)

        let cross = CAShapeLayer()
        let path = CGMutablePath()
        let c = reticleCenter
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            path.move(to: CGPoint(x: c.x + dx * 104, y: c.y + dy * 104))
            path.addLine(to: CGPoint(x: c.x + dx * 122, y: c.y + dy * 122))
            path.move(to: CGPoint(x: c.x + dx * 24, y: c.y + dy * 24))
            path.addLine(to: CGPoint(x: c.x + dx * 40, y: c.y + dy * 40))
        }
        cross.path = path
        cross.strokeColor = Theme.red.cgColor
        cross.lineWidth = 1.5
        root.addSublayer(cross)

        // The red eye: a glowing core that pulses.
        let eye = CAShapeLayer()
        eye.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        eye.position = c
        eye.path = CGPath(ellipseIn: eye.bounds, transform: nil)
        eye.fillColor = Theme.red.cgColor
        eye.shadowColor = Theme.red.cgColor
        eye.shadowOpacity = 1
        eye.shadowRadius = 16
        eye.shadowOffset = .zero
        root.addSublayer(eye)

        let core = CAShapeLayer()
        core.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        core.position = c
        core.path = CGPath(ellipseIn: core.bounds, transform: nil)
        core.fillColor = Theme.hot.cgColor
        root.addSublayer(core)

        if !reduceMotion {
            let glow = CABasicAnimation(keyPath: "shadowRadius")
            glow.fromValue = 8
            glow.toValue = 28
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.9
            scale.toValue = 1.12
            let pulse = CAAnimationGroup()
            pulse.animations = [glow, scale]
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            eye.add(pulse, forKey: "pulse")
        }
    }

    private func buildCornerBrackets(in root: CALayer) {
        let inset: CGFloat = 14, arm: CGFloat = 22
        let w = Self.size.width, h = Self.size.height
        let path = CGMutablePath()
        for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0), (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)] {
            path.move(to: CGPoint(x: x + dx * arm, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + dy * arm))
        }
        let brackets = CAShapeLayer()
        brackets.path = path
        brackets.fillColor = nil
        brackets.strokeColor = Theme.red.withAlphaComponent(0.7).cgColor
        brackets.lineWidth = 2
        root.addSublayer(brackets)
    }

    private func buildProgressBar(in root: CALayer) {
        let track = CALayer()
        track.frame = CGRect(x: 40, y: 176, width: Self.size.width - 160, height: 8)
        track.borderColor = Theme.dimRed.cgColor
        track.borderWidth = 1
        root.addSublayer(track)

        progressFill.frame = CGRect(x: 40, y: 176, width: 0, height: 8)
        progressFill.backgroundColor = Theme.red.cgColor
        progressFill.shadowColor = Theme.red.cgColor
        progressFill.shadowOpacity = 0.9
        progressFill.shadowRadius = 6
        progressFill.shadowOffset = .zero
        root.addSublayer(progressFill)
    }

    private func buildLabels() {
        func place(_ label: NSTextField, _ rect: NSRect) {
            label.frame = rect
            label.drawsBackground = false
            label.isBordered = false
            addSubview(label)
        }

        let glow = NSShadow()
        glow.shadowColor = Theme.red
        glow.shadowBlurRadius = 10
        let title = NSTextField(labelWithAttributedString: NSAttributedString(string: "SH_TERMINATOR", attributes: [
            .font: Theme.mono(30, .heavy),
            .foregroundColor: Theme.red,
            .shadow: glow,
            .kern: 2,
        ]))
        place(title, NSRect(x: 330, y: 438, width: 370, height: 40))

        let subtitle = NSTextField(labelWithString: "CYBERNETIC SECURE SHELL · MODEL 101")
        subtitle.font = Theme.mono(11, .medium)
        subtitle.textColor = Theme.dimRed
        place(subtitle, NSRect(x: 332, y: 420, width: 370, height: 16))

        logLabel.maximumNumberOfLines = 0
        place(logLabel, NSRect(x: 332, y: 200, width: 360, height: 212))

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        percentLabel.textColor = Theme.red
        place(percentLabel, NSRect(x: Self.size.width - 108, y: 171, width: 70, height: 18))

        selectLabel.alphaValue = reduceMotion ? 1 : 0
        place(selectLabel, NSRect(x: 40, y: 148, width: 400, height: 16))

        hintLabel.font = Theme.mono(9)
        hintLabel.textColor = Theme.red.withAlphaComponent(0.35)
        place(hintLabel, NSRect(x: 40, y: 14, width: 500, height: 14))
    }

    /// CRT scanlines and a slow bright band rolling down the screen.
    private func buildScanlines(in root: CALayer) {
        let lines = CAReplicatorLayer()
        lines.frame = root.bounds
        lines.instanceCount = Int(Self.size.height / 3)
        lines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: Self.size.width, height: 1)
        line.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        lines.addSublayer(line)
        root.addSublayer(lines)

        guard !reduceMotion else { return }
        let band = CAGradientLayer()
        band.frame = CGRect(x: 0, y: 0, width: Self.size.width, height: 80)
        band.colors = [NSColor.clear, Theme.red.withAlphaComponent(0.07), NSColor.clear].map(\.cgColor)
        root.addSublayer(band)
        let roll = CABasicAnimation(keyPath: "position.y")
        roll.fromValue = Self.size.height + 40
        roll.toValue = -40
        roll.duration = 2.4
        roll.repeatCount = .infinity
        band.add(roll, forKey: "roll")

        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [1, 0.85, 1, 0.92, 1]
        flicker.duration = 0.25
        flicker.repeatCount = .infinity
        root.add(flicker, forKey: "flicker")
    }
}

/// One layout on offer: a sketch of its panes, its name and its key.
private final class LaunchCard: NSView {
    let layout: LaunchLayout
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isHighlighted = false {
        didSet { updateLook() }
    }

    private let diagram = CAShapeLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "")

    init(layout: LaunchLayout, frame: NSRect) {
        self.layout = layout
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = 4
        layer?.shadowColor = Theme.red.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 12

        // The panes, drawn as a window split into its grid.
        let box = CGRect(x: (frame.width - 72) / 2, y: 46, width: 72, height: 40)
        let path = CGMutablePath()
        path.addRect(box)
        let (rows, cols) = layout.grid
        for col in 1..<cols {
            let x = box.minX + box.width * CGFloat(col) / CGFloat(cols)
            path.move(to: CGPoint(x: x, y: box.minY))
            path.addLine(to: CGPoint(x: x, y: box.maxY))
        }
        for row in 1..<rows {
            let y = box.minY + box.height * CGFloat(row) / CGFloat(rows)
            path.move(to: CGPoint(x: box.minX, y: y))
            path.addLine(to: CGPoint(x: box.maxX, y: y))
        }
        diagram.path = path
        diagram.fillColor = Theme.red.withAlphaComponent(0.08).cgColor
        diagram.lineWidth = 1.5
        layer?.addSublayer(diagram)

        titleLabel.stringValue = layout.title
        titleLabel.font = Theme.mono(13, .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 0, y: 22, width: frame.width, height: 18)

        let detail = NSTextField(labelWithString: layout.detail)
        detail.font = Theme.mono(9)
        detail.textColor = Theme.dimRed
        detail.alignment = .center
        detail.frame = NSRect(x: 0, y: 8, width: frame.width, height: 13)

        keyLabel.stringValue = "[\(layout.key)]"
        keyLabel.font = Theme.mono(10, .bold)
        keyLabel.frame = NSRect(x: 8, y: frame.height - 20, width: 40, height: 14)

        for label in [titleLabel, detail, keyLabel] {
            addSubview(label)
        }
        updateLook()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func updateLook() {
        layer?.borderWidth = isHighlighted ? 1.5 : 1
        layer?.borderColor = (isHighlighted ? Theme.red : Theme.red.withAlphaComponent(0.3)).cgColor
        layer?.backgroundColor = Theme.red.withAlphaComponent(isHighlighted ? 0.12 : 0.03).cgColor
        layer?.shadowOpacity = isHighlighted ? 0.8 : 0
        diagram.strokeColor = (isHighlighted ? Theme.red : Theme.dimRed).cgColor
        titleLabel.textColor = isHighlighted ? Theme.hot : Theme.red
        keyLabel.textColor = isHighlighted ? Theme.red : Theme.dimRed
    }

    /// A brief white-hot flash when picked.
    func flash() {
        layer?.borderColor = Theme.hot.cgColor
        layer?.backgroundColor = Theme.red.withAlphaComponent(0.3).cgColor
        diagram.strokeColor = Theme.hot.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    /// The labels inside take no clicks of their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Draws on top of everything but takes no clicks.
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
