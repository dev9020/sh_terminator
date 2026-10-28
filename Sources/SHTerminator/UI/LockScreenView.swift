import AppKit
import QuartzCore

/// What a window shows instead of its panes while `PrivacyLock` is engaged:
/// red Matrix-style digital rain behind a Terminator HUD (the launcher's
/// reticle, brackets and scanlines, plus status readouts). Everything on it
/// is fixed or random text, never anything from a pane. It takes first
/// responder and swallows keystrokes; Return unlocks.
///
/// The animation only runs while the view is in a window that is at least
/// partly on screen, and is left out entirely with Reduce Motion.
final class LockScreenView: NSView {
    /// How far above the middle of the view the reticle (and the icon in
    /// it) sits; the text goes below it.
    fileprivate static let reticleRise: CGFloat = 80

    private let scene = LockSceneView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let unlockButton = NSButton(title: "Unlock…", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor

        scene.frame = bounds
        scene.autoresizingMask = [.width, .height]
        addSubview(scene)

        iconView.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        iconView.contentTintColor = Theme.hot
        titleLabel.font = Theme.mono(22, .bold)
        titleLabel.textColor = Theme.red
        let glow = NSShadow()
        glow.shadowColor = Theme.red
        glow.shadowBlurRadius = 10
        titleLabel.shadow = glow
        subtitleLabel.font = Theme.mono(11)
        subtitleLabel.textColor = Theme.muted
        unlockButton.bezelStyle = .rounded
        unlockButton.keyEquivalent = "\r"
        unlockButton.target = self
        unlockButton.action = #selector(unlockClicked(_:))

        // The icon sits in the middle of the reticle; the text goes below
        // the reticle's outer ticks (122pt from its centre).
        let stack = NSStackView(views: [titleLabel, subtitleLabel, unlockButton])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(18, after: subtitleLabel)
        for view in [iconView, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Self.reticleRise),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: iconView.centerYAnchor, constant: 132),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(for state: PrivacyLock.State) {
        let locked = state == .locked
        let symbol = locked ? "lock.fill" : "eye.slash.fill"
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: locked ? "Locked" : "Hidden")
        titleLabel.stringValue = locked ? "// SYSTEM LOCKED" : "// VISUAL FEED BLOCKED"
        subtitleLabel.stringValue = locked
            ? "IDENTITY VERIFICATION REQUIRED · TOUCH ID OR PASSWORD"
            : "HIDDEN WHILE SH_TERMINATOR IS IN THE BACKGROUND"
        unlockButton.isHidden = !locked
        scene.state = state
    }

    override var isOpaque: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Swallow everything: nothing typed here may reach a shell.
    }

    @objc private func unlockClicked(_ sender: Any?) {
        PrivacyLock.shared.unlock()
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        iconView.contentTintColor = Theme.hot
        titleLabel.textColor = Theme.red
        let glow = NSShadow()
        glow.shadowColor = Theme.red
        glow.shadowBlurRadius = 10
        titleLabel.shadow = glow
        subtitleLabel.textColor = Theme.muted
        scene.applyTheme()
    }
}

/// The animated backdrop of `LockScreenView`, as a layer-hosting view: the
/// rain, a dark halo behind the centre text, the HUD and its readouts.
private final class LockSceneView: NSView {
    var state: PrivacyLock.State = .locked {
        didSet { renderReadouts() }
    }

    private var reticleCenter: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY + LockScreenView.reticleRise)
    }

    private struct RainColumn {
        let trail: CATextLayer
        let head: CATextLayer
        let length: Int
    }

    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789ABCDEF:=+*<>")
    private static let rainFont = Theme.mono(13)
    /// Width of a rain column and height of one glyph in it.
    private static let cell: CGFloat = 16

    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let rainLayer = CALayer()
    private let haloLayer = CAGradientLayer()
    private let hudLayer = CALayer()
    private let statusText = CATextLayer()
    private let threatText = CATextLayer()
    private let hexText = CATextLayer()
    private let footerText = CATextLayer()

    private var columns: [RainColumn] = []
    private var rainSize: CGSize = .zero
    private var hudSize: CGSize = .zero
    private var scale: CGFloat = 0
    private var timer: Timer?
    private var ticks = 0
    private var blink = true

    init() {
        super.init(frame: .zero)
        let root = CALayer()
        root.backgroundColor = Theme.background.cgColor
        layer = root
        wantsLayer = true
        root.addSublayer(rainLayer)
        root.addSublayer(haloLayer)
        root.addSublayer(hudLayer)
        haloLayer.type = .radial
        let background = Theme.background
        haloLayer.colors = [background.withAlphaComponent(0.95), background.withAlphaComponent(0.85), background.withAlphaComponent(0)].map(\.cgColor)
        haloLayer.locations = [0, 0.45, 1]
        for text in [statusText, threatText, hexText, footerText] {
            text.anchorPoint = .zero
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(systemDidWake(_:)), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Building

    override func layout() {
        super.layout()
        let newScale = window?.backingScaleFactor ?? 2
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if newScale != scale {
            scale = newScale
            rainSize = .zero
            hudSize = .zero
        }
        // The rain is the expensive part: rebuilt only once a live resize
        // ends, and while it lasts the existing columns just stay put.
        if size != rainSize, !inLiveResize {
            rainSize = size
            buildRain(size: size)
        }
        if size != hudSize {
            hudSize = size
            buildHUD(size: size)
        }
        CATransaction.commit()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// Forces the rain and the HUD to rebuild from scratch, which bakes in
    /// whatever `Theme` now says.
    func applyTheme() {
        layer?.backgroundColor = Theme.background.cgColor
        let background = Theme.background
        haloLayer.colors = [background.withAlphaComponent(0.95), background.withAlphaComponent(0.85), background.withAlphaComponent(0)].map(\.cgColor)
        rainSize = .zero
        hudSize = .zero
        needsLayout = true
    }

    private func buildRain(size: CGSize) {
        rainLayer.sublayers = nil
        rainLayer.frame = CGRect(origin: .zero, size: size)
        columns = []
        let cell = Self.cell
        for index in 0..<Int(ceil(size.width / cell)) where Double.random(in: 0..<1) < 0.7 {
            let length = Int.random(in: 6...26)
            let height = CGFloat(length) * cell
            // Fainter columns fall slower, as if further away.
            let depth = Float.random(in: 0.2...0.9)

            let column = CALayer()
            column.anchorPoint = .zero
            column.bounds = CGRect(x: 0, y: 0, width: cell, height: height)
            column.position = CGPoint(x: CGFloat(index) * cell, y: CGFloat.random(in: -height...size.height))
            column.opacity = depth

            let trail = CATextLayer()
            trail.frame = CGRect(x: 0, y: cell, width: cell, height: height - cell)
            trail.contentsScale = scale
            trail.string = Self.rain(length - 1, color: Theme.red)
            let fade = CAGradientLayer()
            fade.frame = trail.bounds
            fade.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
            fade.startPoint = CGPoint(x: 0.5, y: 0)
            fade.endPoint = CGPoint(x: 0.5, y: 1)
            trail.mask = fade

            let head = CATextLayer()
            head.frame = CGRect(x: 0, y: 0, width: cell, height: cell)
            head.contentsScale = scale
            head.string = Self.rain(1, color: Theme.hot)
            head.shadowColor = Theme.red.cgColor
            head.shadowOpacity = 1
            head.shadowRadius = 4
            head.shadowOffset = .zero
            head.shouldRasterize = true
            head.rasterizationScale = scale

            column.addSublayer(trail)
            column.addSublayer(head)
            rainLayer.addSublayer(column)
            columns.append(RainColumn(trail: trail, head: head, length: length))

            guard !reduceMotion else { continue }
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = size.height
            fall.toValue = -height
            fall.duration = Double(size.height + height) / Double(60 + 220 * depth)
            fall.repeatCount = .infinity
            fall.timeOffset = Double.random(in: 0..<fall.duration)
            column.add(fall, forKey: "fall")
        }
    }

    private func buildHUD(size: CGSize) {
        let r = min(size.width, size.height) * 0.6
        haloLayer.frame = CGRect(origin: .zero, size: size)
        haloLayer.startPoint = CGPoint(x: reticleCenter.x / size.width, y: (reticleCenter.y - 90) / size.height)
        haloLayer.endPoint = CGPoint(x: haloLayer.startPoint.x + r / size.width, y: haloLayer.startPoint.y + r / size.height)

        hudLayer.sublayers = nil
        hudLayer.removeAllAnimations()
        hudLayer.frame = CGRect(origin: .zero, size: size)
        HUD.cornerBrackets(in: hudLayer, size: size)
        HUD.reticle(in: hudLayer, center: reticleCenter, animated: !reduceMotion)
        buildCore()
        for text in [statusText, threatText, hexText, footerText] {
            text.contentsScale = scale
            hudLayer.addSublayer(text)
        }
        HUD.scanlines(in: hudLayer, size: size, animated: !reduceMotion)
        renderReadouts()
    }

    /// The red eye behind the lock icon, pulsing.
    private func buildCore() {
        let core = CAShapeLayer()
        core.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        core.position = reticleCenter
        core.path = CGPath(ellipseIn: core.bounds, transform: nil)
        core.fillColor = Theme.red.withAlphaComponent(0.55).cgColor
        core.shadowColor = Theme.red.cgColor
        core.shadowOpacity = 1
        core.shadowRadius = 18
        core.shadowOffset = .zero
        hudLayer.addSublayer(core)

        guard !reduceMotion else { return }
        let glow = CABasicAnimation(keyPath: "shadowRadius")
        glow.fromValue = 10
        glow.toValue = 30
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.08
        let pulse = CAAnimationGroup()
        pulse.animations = [glow, scale]
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        core.add(pulse, forKey: "pulse")
    }

    // MARK: - Readouts

    private func renderReadouts() {
        let size = hudSize
        guard size.width > 0 else { return }
        let inset: CGFloat = 30
        let locked = state == .locked
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let status: [(String, String)] = locked
            ? [("TERMINAL SESSIONS", "SEALED"), ("INPUT ROUTING", "SEVERED"), ("OPERATOR", "NOT DETECTED"), ("BIOMETRIC SCAN", "STANDBY")]
            : [("TERMINAL SESSIONS", "MASKED"), ("INPUT ROUTING", "SEVERED"), ("OPERATOR", "ELSEWHERE"), ("VISUAL FEED", "BLOCKED")]
        let prompt = locked ? "AWAITING AUTHORIZATION " : "RETURN TO THIS APP TO RESUME "
        place(statusText, Self.readout(
            title: "SH_TERMINATOR OS v1.0 // SECURITY SUBSYSTEM",
            rows: status,
            last: prompt + (blink ? "█" : " ")
        ), x: inset, top: size.height - inset, rightAligned: false)

        let threat: [(String, String)] = locked
            ? [("SUBJECT", "UNKNOWN"), ("MATCH", "NEGATIVE")]
            : [("SUBJECT", "OUT OF VIEW"), ("MATCH", "N/A")]
        place(threatText, Self.readout(
            title: "THREAT ASSESSMENT",
            rows: threat,
            last: blink ? (locked ? "ACCESS DENIED" : "ACCESS SUSPENDED") : " ",
            rightAligned: true
        ), x: size.width - inset, top: size.height - inset, rightAligned: true)

        place(hexText, Self.hexDump(), x: size.width - inset, top: inset + 5 * 15, rightAligned: true)
        place(footerText, NSAttributedString(
            string: "SCAN MODE 43984 // DIGITAL RAIN FEED ACTIVE",
            attributes: [.font: Theme.mono(10), .foregroundColor: Theme.dimRed]
        ), x: inset, top: inset + 14, rightAligned: false)

        CATransaction.commit()
    }

    /// Sizes `layer` to fit `text` and puts its top edge at `top`, starting
    /// at `x` (or ending there, if `rightAligned`).
    private func place(_ layer: CATextLayer, _ text: NSAttributedString, x: CGFloat, top: CGFloat, rightAligned: Bool) {
        let size = text.boundingRect(with: NSSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin]).size
        let width = ceil(size.width) + 2, height = ceil(size.height) + 2
        layer.string = text
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.position = CGPoint(x: rightAligned ? x - width : x, y: top - height)
    }

    private static func readout(title: String, rows: [(String, String)], last: String, rightAligned: Bool = false) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = rightAligned ? .right : .left
        style.lineSpacing = 3
        let bright: [NSAttributedString.Key: Any] = [.font: Theme.mono(11), .foregroundColor: Theme.red, .paragraphStyle: style]
        let dim: [NSAttributedString.Key: Any] = [.font: Theme.mono(11), .foregroundColor: Theme.dimRed, .paragraphStyle: style]
        let hot: [NSAttributedString.Key: Any] = [.font: Theme.mono(11, .bold), .foregroundColor: Theme.hot, .paragraphStyle: style]

        let text = NSMutableAttributedString(string: title + "\n\n", attributes: bright)
        for (name, value) in rows {
            let dots = String(repeating: ".", count: max(2, 20 - name.count))
            text.append(NSAttributedString(string: "> \(name) ", attributes: bright))
            text.append(NSAttributedString(string: dots, attributes: dim))
            text.append(NSAttributedString(string: " [\(value)]\n", attributes: hot))
        }
        text.append(NSAttributedString(string: "\n" + last, attributes: hot))
        return text
    }

    /// Random hex, purely decorative.
    private static func hexDump() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.lineSpacing = 2
        let lines = (0..<5).map { _ in
            "0x" + (0..<4).map { _ in String(format: "%04X", Int.random(in: 0...0xFFFF)) }.joined(separator: " ")
        }
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: Theme.mono(10), .foregroundColor: Theme.dimRed, .paragraphStyle: style,
        ])
    }

    /// A vertical string of `count` random glyphs, one per cell.
    private static func rain(_ count: Int, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = cell
        style.maximumLineHeight = cell
        let text = (0..<count).map { _ in String(glyphs.randomElement()!) }.joined(separator: "\n")
        return NSAttributedString(string: text, attributes: [.font: rainFont, .foregroundColor: color, .paragraphStyle: style])
    }

    // MARK: - Running

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionDidChange(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Every time the lock screen is actually presented (whichever of
        // PrivacyLock's triggers caused it — Lock Now, idle timeout, the
        // Mac's own lock/sleep, …), rebuild from scratch rather than
        // resuming whatever was left over from the last time: a resumed,
        // long-paused layer tree is where the animation has been seen to
        // glitch, while a fresh one is known to run cleanly.
        if window != nil {
            rainSize = .zero
            hudSize = .zero
            needsLayout = true
        }
        updateRunning()
    }

    @objc private func occlusionDidChange(_ notification: Notification) {
        updateRunning()
    }

    /// While the screens sleep or the session is switched away (the Mac's
    /// own lock screen), Core Animation can drop the layers' animations: the
    /// rain and HUD would stay frozen while the timer still changes the
    /// text. The scene is rebuilt, and running re-checked in case no
    /// occlusion change was posted.
    @objc private func systemDidWake(_ notification: Notification) {
        rainSize = .zero
        hudSize = .zero
        needsLayout = true
        updateRunning()
    }

    /// Animates only while on screen: off the window (unlocked) or with the
    /// window fully hidden, the layer tree is paused and the timer stopped.
    private func updateRunning() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        setRunning(visible && !reduceMotion)
    }

    private func setRunning(_ running: Bool) {
        guard let root = layer, running != (timer != nil) else { return }
        if running {
            if root.speed == 0 {
                let pausedAt = root.timeOffset
                root.speed = 1
                root.timeOffset = 0
                root.beginTime = 0
                root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else {
            root.timeOffset = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            timer?.invalidate()
            timer = nil
        }
    }

    /// Glyphs change as they fall, the hex scrolls and the cursors blink.
    private func tick() {
        ticks += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !columns.isEmpty {
            for _ in 0..<max(1, columns.count / 10) {
                let column = columns.randomElement()!
                column.trail.string = Self.rain(column.length - 1, color: Theme.red)
            }
            for _ in 0..<max(1, columns.count / 4) {
                columns.randomElement()!.head.string = Self.rain(1, color: Theme.hot)
            }
        }
        CATransaction.commit()
        if ticks % 3 == 0 || ticks % 5 == 0 {
            if ticks % 5 == 0 { blink.toggle() }
            renderReadouts()
        }
    }
}
