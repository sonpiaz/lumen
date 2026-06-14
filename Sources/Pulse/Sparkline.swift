import AppKit

/// Renders a compact CPU-history sparkline for the menu bar. Returns a template
/// image (black on transparent) so the system tints it to match the menu bar in
/// both light and dark mode — quiet and native.
enum Sparkline {
    static func image(_ values: [Double], size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        guard values.count >= 2 else { return template(img) }

        let w = size.width, h = size.height
        let pad: CGFloat = 1.5
        let plotH = h - pad * 2
        let n = values.count
        let stepX = w / CGFloat(n - 1)

        func point(_ i: Int) -> NSPoint {
            let v = max(0, min(100, values[i])) / 100
            return NSPoint(x: CGFloat(i) * stepX,
                           y: pad + CGFloat(v) * plotH)
        }

        // Soft area fill under the line for a bit of weight.
        let area = NSBezierPath()
        area.move(to: NSPoint(x: 0, y: pad))
        for i in 0..<n { area.line(to: point(i)) }
        area.line(to: NSPoint(x: w, y: pad))
        area.close()
        NSColor.black.withAlphaComponent(0.18).setFill()
        area.fill()

        // The line itself.
        let line = NSBezierPath()
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.move(to: point(0))
        for i in 1..<n { line.line(to: point(i)) }
        NSColor.black.setStroke()
        line.stroke()

        return template(img)
    }

    private static func template(_ img: NSImage) -> NSImage {
        img.isTemplate = true
        return img
    }
}
