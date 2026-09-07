import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
        NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.22, blue: 0.23, alpha: 1),
                   ending: NSColor(srgbRed: 0.025, green: 0.075, blue: 0.12, alpha: 1))!.draw(in: tile, angle: -70)
        let monitor = NSBezierPath(roundedRect: NSRect(x: 320, y: 388, width: 456, height: 328), xRadius: 30, yRadius: 30)
        NSColor(srgbRed: 0.24, green: 0.88, blue: 0.71, alpha: 1).setStroke()
        monitor.lineWidth = 27
        monitor.stroke()
        NSColor(srgbRed: 0.24, green: 0.88, blue: 0.71, alpha: 0.12).setFill()
        monitor.fill()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 549, y: 380)); stand.line(to: NSPoint(x: 549, y: 318))
        stand.move(to: NSPoint(x: 473, y: 313)); stand.line(to: NSPoint(x: 626, y: 313))
        stand.lineWidth = 26; stand.lineCapStyle = .round; stand.stroke()
        let laptop = NSBezierPath(roundedRect: NSRect(x: 194, y: 283, width: 299, height: 212), xRadius: 22, yRadius: 22)
        NSColor(srgbRed: 0.04, green: 0.10, blue: 0.15, alpha: 1).setFill(); laptop.fill()
        NSColor(srgbRed: 0.77, green: 0.85, blue: 0.87, alpha: 1).setStroke()
        laptop.lineWidth = 22; laptop.stroke()
        let base = NSBezierPath()
        base.move(to: NSPoint(x: 169, y: 261)); base.line(to: NSPoint(x: 519, y: 261))
        base.lineWidth = 25; base.lineCapStyle = .round; base.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 1 ? "" : "@2x"
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
