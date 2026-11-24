import AppKit

/// The menu bar symbol: a photo with a small badge in its lower right corner. Drawn as a
/// template image, so macOS colours it like its own symbols (light, dark, highlighted).
///
/// While copying, two arrows turn in the badge (12 frames per turn); afterwards a check mark
/// shows for a moment, as Dropbox and OneDrive do.
enum TrayIcon {
    static let size = NSSize(width: 20, height: 18)
    static let frameCount = 12

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ state: TrayState, frame: Int = 0) -> NSImage {
        let key = "\(state.rawValue)-\(state == .busy ? frame % frameCount : 0)"
        if let image = cache[key] { return image }
        let angle = CGFloat(frame % frameCount) * (360 / CGFloat(frameCount))
        let image = NSImage(size: size, flipped: true) { _ in
            draw(state, angle: angle)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LightCraft Pic Watcher"
        cache[key] = image
        return image
    }

    /// Coordinates as in the mockup's SVG (20 × 18, origin top left).
    private static func draw(_ state: TrayState, angle: CGFloat) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 14, height: 11), xRadius: 2.2, yRadius: 2.2)
        frame.lineWidth = 1.4
        frame.stroke()

        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: 3.6, y: 11.4))
        hills.line(to: NSPoint(x: 6.7, y: 7.9))
        hills.line(to: NSPoint(x: 9.1, y: 10.3))
        hills.line(to: NSPoint(x: 10.8, y: 8.6))
        hills.line(to: NSPoint(x: 13.3, y: 11.4))
        hills.lineWidth = 1.4
        hills.lineCapStyle = .round
        hills.lineJoinStyle = .round
        hills.stroke()

        NSBezierPath(ovalIn: NSRect(x: 10.5, y: 4.8, width: 2.2, height: 2.2)).fill()

        guard state != .idle, let context = NSGraphicsContext.current else { return }
        let center = NSPoint(x: 15.5, y: 13)

        // Cut a hole for the badge out of the photo.
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 4.3, y: center.y - 4.3, width: 8.6, height: 8.6)).fill()
        context.compositingOperation = .sourceOver

        switch state {
        case .busy:
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: angle)
            transform.translateX(by: -center.x, yBy: -center.y)
            context.saveGraphicsState()
            transform.concat()
            for start in [190.0, 10.0] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 2.4, startAngle: start, endAngle: start + 140, clockwise: false)
                arc.lineWidth = 1.15
                arc.lineCapStyle = .round
                arc.stroke()
            }
            for points in [[NSPoint(x: 18.1, y: 12.7), NSPoint(x: 18.4, y: 11.3), NSPoint(x: 16.8, y: 12.2)],
                           [NSPoint(x: 12.9, y: 13.3), NSPoint(x: 12.6, y: 14.7), NSPoint(x: 14.2, y: 13.8)]] {
                let head = NSBezierPath()
                head.move(to: points[0]); head.line(to: points[1]); head.line(to: points[2]); head.close()
                head.fill()
            }
            context.restoreGraphicsState()
        case .done:
            NSBezierPath(ovalIn: NSRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)).fill()
            context.compositingOperation = .clear
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 13.9, y: 13.1))
            check.line(to: NSPoint(x: 15.0, y: 14.2))
            check.line(to: NSPoint(x: 17.1, y: 11.9))
            check.lineWidth = 1.2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
            context.compositingOperation = .sourceOver
        case .paused:
            NSBezierPath(roundedRect: NSRect(x: 14.0, y: 11.1, width: 1.1, height: 3.8), xRadius: 0.4, yRadius: 0.4).fill()
            NSBezierPath(roundedRect: NSRect(x: 15.9, y: 11.1, width: 1.1, height: 3.8), xRadius: 0.4, yRadius: 0.4).fill()
        case .warn:
            NSBezierPath(ovalIn: NSRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)).fill()
            context.compositingOperation = .clear
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: 15.5, y: 11.3))
            bar.line(to: NSPoint(x: 15.5, y: 13.4))
            bar.lineWidth = 1.2
            bar.lineCapStyle = .round
            bar.stroke()
            NSBezierPath(ovalIn: NSRect(x: 14.9, y: 14.2, width: 1.2, height: 1.2)).fill()
            context.compositingOperation = .sourceOver
        case .idle:
            break
        }
    }
}
