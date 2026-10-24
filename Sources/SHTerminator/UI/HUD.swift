import AppKit
import QuartzCore

/// The pieces of the red Terminator HUD shared by the launcher and the lock
/// screen. Each adds its layers to `root`, in `root`'s (unflipped)
/// coordinates; `animated: false` (Reduce Motion) leaves the motion out.
@MainActor
enum HUD {
    /// Two counter-rotating dashed rings, a fixed inner ring and crosshair
    /// ticks around `center`.
    static func reticle(in root: CALayer, center: CGPoint, animated: Bool) {
        func ring(radius: CGFloat, width: CGFloat, color: NSColor, dash: [NSNumber]? = nil) -> CAShapeLayer {
            let ring = CAShapeLayer()
            ring.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            ring.position = center
            ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = width
            ring.lineDashPattern = dash
            root.addSublayer(ring)
            return ring
        }
        func spin(_ layer: CALayer, seconds: CFTimeInterval, clockwise: Bool) {
            guard animated else { return }
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
        let c = center
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
    }

    /// L-shaped brackets in the four corners of a `size` area.
    static func cornerBrackets(in root: CALayer, size: CGSize) {
        let inset: CGFloat = 14, arm: CGFloat = 22
        let w = size.width, h = size.height
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

    /// CRT scanlines over a `size` area, with a bright band rolling down and
    /// a slight flicker of `root`.
    static func scanlines(in root: CALayer, size: CGSize, animated: Bool) {
        let lines = CAReplicatorLayer()
        lines.frame = CGRect(origin: .zero, size: size)
        lines.instanceCount = Int(size.height / 3)
        lines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: size.width, height: 1)
        line.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        lines.addSublayer(line)
        root.addSublayer(lines)

        guard animated else { return }
        let band = CAGradientLayer()
        band.frame = CGRect(x: 0, y: 0, width: size.width, height: 80)
        band.colors = [NSColor.clear, Theme.red.withAlphaComponent(0.07), NSColor.clear].map(\.cgColor)
        root.addSublayer(band)
        let roll = CABasicAnimation(keyPath: "position.y")
        roll.fromValue = size.height + 40
        roll.toValue = -40
        roll.duration = 2.4 * max(1, size.height / 500)
        roll.repeatCount = .infinity
        band.add(roll, forKey: "roll")

        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [1, 0.85, 1, 0.92, 1]
        flicker.duration = 0.25
        flicker.repeatCount = .infinity
        root.add(flicker, forKey: "flicker")
    }
}
