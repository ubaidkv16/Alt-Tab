import AppKit

// Generates Resources/AppIcon.icns: a macOS-style rounded square with two
// overlapping window glyphs.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)

    NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.32, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1)])?
        .draw(in: squircle, angle: -90)

    func window(_ r: NSRect, fill: NSColor, bar: NSColor) {
        let p = NSBezierPath(roundedRect: r, xRadius: s * 0.035, yRadius: s * 0.035)
        NSColor.black.withAlphaComponent(0.35).setFill()
        p.transformed(dx: 0, dy: -s * 0.012).fill()
        fill.setFill(); p.fill()
        let barRect = NSRect(x: r.minX, y: r.maxY - r.height * 0.2, width: r.width, height: r.height * 0.2)
        NSGraphicsContext.current?.saveGraphicsState()
        p.addClip(); bar.setFill(); barRect.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    window(NSRect(x: s * 0.18, y: s * 0.20, width: s * 0.46, height: s * 0.36),
           fill: NSColor(calibratedWhite: 0.62, alpha: 1), bar: NSColor(calibratedWhite: 0.48, alpha: 1))
    window(NSRect(x: s * 0.36, y: s * 0.40, width: s * 0.46, height: s * 0.36),
           fill: NSColor(calibratedRed: 0.98, green: 0.98, blue: 1.0, alpha: 1),
           bar: NSColor(calibratedRed: 0.29, green: 0.55, blue: 0.98, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSBezierPath {
    func transformed(dx: CGFloat, dy: CGFloat) -> NSBezierPath {
        let t = AffineTransform(translationByX: dx, byY: dy)
        let c = copy() as! NSBezierPath
        c.transform(using: t)
        return c
    }
}

for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let rep = draw(size * scale)
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
print("wrote \(out)")
