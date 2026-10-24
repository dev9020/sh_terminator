// Renders the app icon in code (no third-party artwork) into an .iconset
// folder; Scripts/make-icon.sh then turns it into Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift <output.iconset>
import AppKit

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    }
    // The app's HUD palette (see Sources/SHTerminator/UI/Theme.swift).
    func red(_ a: CGFloat = 1) -> CGColor { rgb(255, 33, 20, a) }
    let hot = rgb(255, 220, 205)

    // Standard macOS icon grid: 824/1024 body with a soft drop shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let w = body.width
    let radius = w * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(9, 0, 0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Background: near-black with a deep red glow around the eye.
    let eye = CGPoint(x: body.midX, y: body.midY + w * 0.06)
    ctx.drawRadialGradient(
        gradient([rgb(70, 8, 5), rgb(24, 2, 1), rgb(8, 0, 0)], [0, 0.55, 1]),
        startCenter: eye, startRadius: 0,
        endCenter: eye, endRadius: w * 0.75,
        options: [.drawsAfterEndLocation]
    )

    // CRT scanlines (only where they can be told apart).
    if s >= 64 {
        let step = max(2, s * 0.012)
        ctx.setFillColor(rgb(0, 0, 0, 0.28))
        var y = body.minY
        while y < body.maxY {
            ctx.fill(CGRect(x: body.minX, y: y, width: w, height: step / 2))
            y += step
        }
    }

    // HUD corner brackets.
    let bracketInset = w * 0.09, arm = w * 0.12
    ctx.setStrokeColor(red(0.65))
    ctx.setLineWidth(max(1, w * 0.018))
    ctx.setLineCap(.square)
    for (x, y, dx, dy) in [
        (body.minX + bracketInset, body.minY + bracketInset, 1.0, 1.0),
        (body.maxX - bracketInset, body.minY + bracketInset, -1.0, 1.0),
        (body.minX + bracketInset, body.maxY - bracketInset, 1.0, -1.0),
        (body.maxX - bracketInset, body.maxY - bracketInset, -1.0, -1.0),
    ] {
        ctx.move(to: CGPoint(x: x + dx * arm, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y + dy * arm))
    }
    ctx.strokePath()

    // Targeting reticle: a dashed outer ring, a broken thick ring, ticks.
    func ring(_ r: CGFloat, width: CGFloat, color: CGColor, dash: [CGFloat] = []) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash.map { $0 * w }) }
        ctx.strokeEllipse(in: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
    ring(w * 0.31, width: max(1, w * 0.012), color: red(0.5), dash: s >= 64 ? [0.05, 0.022] : [])
    ring(w * 0.24, width: max(1, w * 0.032), color: red(0.9), dash: [0.16, 0.07])
    ring(w * 0.165, width: max(1, w * 0.008), color: red(0.45))

    ctx.setStrokeColor(red())
    ctx.setLineWidth(max(1, w * 0.016))
    for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
        ctx.move(to: CGPoint(x: eye.x + dx * w * 0.34, y: eye.y + dy * w * 0.34))
        ctx.addLine(to: CGPoint(x: eye.x + dx * w * 0.41, y: eye.y + dy * w * 0.41))
        ctx.move(to: CGPoint(x: eye.x + dx * w * 0.085, y: eye.y + dy * w * 0.085))
        ctx.addLine(to: CGPoint(x: eye.x + dx * w * 0.13, y: eye.y + dy * w * 0.13))
    }
    ctx.strokePath()

    // The red eye: glow, disc, white-hot core.
    ctx.drawRadialGradient(
        gradient([red(0.75), red(0)]),
        startCenter: eye, startRadius: 0,
        endCenter: eye, endRadius: w * 0.17,
        options: []
    )
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: red())
    ctx.setFillColor(red())
    let disc = w * 0.062
    ctx.fillEllipse(in: CGRect(x: eye.x - disc, y: eye.y - disc, width: disc * 2, height: disc * 2))
    ctx.restoreGState()
    let core = w * 0.026
    ctx.setFillColor(hot)
    ctx.fillEllipse(in: CGRect(x: eye.x - core, y: eye.y - core, width: core * 2, height: core * 2))

    // The prompt "❯_" in the bottom-left corner: it is a terminal.
    if s >= 32 {
        let cx = body.minX + w * 0.165
        let cy = body.minY + w * 0.185
        let chevH = w * 0.1, chevW = w * 0.06, stroke = w * 0.026
        let glyph = CGMutablePath()
        glyph.move(to: CGPoint(x: cx, y: cy + chevH / 2))
        glyph.addLine(to: CGPoint(x: cx + chevW, y: cy))
        glyph.addLine(to: CGPoint(x: cx, y: cy - chevH / 2))
        let prompt = CGMutablePath()
        prompt.addPath(glyph.copy(strokingWithWidth: stroke, lineCap: .square, lineJoin: .miter, miterLimit: 10))
        prompt.addRect(CGRect(x: cx + chevW + w * 0.035, y: cy - chevH / 2 - stroke / 2, width: w * 0.07, height: stroke))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.02, color: red())
        ctx.addPath(prompt)
        ctx.setFillColor(red())
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Thin red rim.
    let line = max(1, s * 0.006)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: line / 2, dy: line / 2),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(red(0.4))
    ctx.setLineWidth(line)
    ctx.strokePath()
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
