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

    // Standard macOS icon grid: 824/1024 body with a soft drop shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(12, 16, 26))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep night-blue gradient.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(34, 44, 68), rgb(14, 18, 30), rgb(6, 8, 14)], [0, 0.55, 1]),
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )
    // Soft teal glow behind the prompt.
    ctx.drawRadialGradient(
        gradient([rgb(40, 220, 190, 0.28), rgb(40, 220, 190, 0)]),
        startCenter: CGPoint(x: body.midX - body.width * 0.08, y: body.midY), startRadius: 0,
        endCenter: CGPoint(x: body.midX - body.width * 0.08, y: body.midY), endRadius: body.width * 0.55,
        options: []
    )

    // Split-pane hint: a faint divider grid, like the app's panes.
    let line = max(1, s * 0.006)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.07))
    ctx.setLineWidth(line)
    ctx.move(to: CGPoint(x: body.minX + body.width * 0.62, y: body.minY))
    ctx.addLine(to: CGPoint(x: body.minX + body.width * 0.62, y: body.maxY))
    ctx.move(to: CGPoint(x: body.minX + body.width * 0.62, y: body.midY))
    ctx.addLine(to: CGPoint(x: body.maxX, y: body.midY))
    ctx.strokePath()

    // Title-bar traffic lights.
    let dot = body.width * 0.045
    let dotY = body.maxY - body.width * 0.1
    for (i, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
        let x = body.minX + body.width * 0.1 + CGFloat(i) * dot * 1.6
        ctx.setFillColor(c.copy(alpha: 0.9)!)
        ctx.fillEllipse(in: CGRect(x: x, y: dotY - dot / 2, width: dot, height: dot))
    }
    ctx.restoreGState()

    // Prompt glyph "❯_" with a teal→green gradient fill.
    let glyph = CGMutablePath()
    let cx = body.minX + body.width * 0.2
    let cy = body.midY - body.width * 0.02
    let chevH = body.width * 0.36
    let chevW = body.width * 0.22
    let stroke = body.width * 0.085
    glyph.move(to: CGPoint(x: cx, y: cy + chevH / 2))
    glyph.addLine(to: CGPoint(x: cx + chevW, y: cy))
    glyph.addLine(to: CGPoint(x: cx, y: cy - chevH / 2))
    let chevron = glyph.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10)

    let underscore = CGPath(
        roundedRect: CGRect(x: cx + chevW + body.width * 0.1, y: cy - chevH / 2 - stroke / 2,
                            width: body.width * 0.2, height: stroke),
        cornerWidth: stroke / 2, cornerHeight: stroke / 2, transform: nil
    )

    let prompt = CGMutablePath()
    prompt.addPath(chevron)
    prompt.addPath(underscore)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: rgb(60, 240, 200, 0.6))
    ctx.addPath(prompt)
    ctx.setFillColor(rgb(60, 240, 200))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(prompt)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(110, 255, 220), rgb(40, 210, 150)]),
        start: CGPoint(x: cx, y: cy + chevH / 2),
        end: CGPoint(x: cx + body.width * 0.6, y: cy - chevH / 2),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // Star badge — "favorites".
    let starCenter = CGPoint(x: body.maxX - body.width * 0.17, y: body.minY + body.width * 0.17)
    let outer = body.width * 0.105
    let star = CGMutablePath()
    for i in 0..<10 {
        let r = i % 2 == 0 ? outer : outer * 0.45
        let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
        let p = CGPoint(x: starCenter.x + r * cos(a), y: starCenter.y + r * sin(a))
        i == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath()
    let roundedStar = star.copy(strokingWithWidth: outer * 0.18, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: rgb(255, 196, 60, 0.55))
    ctx.addPath(star.union(roundedStar))
    ctx.setFillColor(rgb(255, 196, 60))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(star.union(roundedStar))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(255, 224, 120), rgb(255, 160, 40)]),
        start: CGPoint(x: starCenter.x, y: starCenter.y + outer),
        end: CGPoint(x: starCenter.x, y: starCenter.y - outer),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // Thin inner highlight on the rim.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: line / 2, dy: line / 2),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.12))
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
