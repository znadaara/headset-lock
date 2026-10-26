// Draws the app icon: white headphones with a lock badge on a blue squircle.
// Run: swift tools/make-icon.swift   (writes resources/AppIcon.icns)

import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824 pt squircle centered on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.42, green: 0.70, blue: 1.0, alpha: 1),
                        NSColor(red: 0.07, green: 0.33, blue: 0.86, alpha: 1),
                        NSColor(red: 0.03, green: 0.16, blue: 0.52, alpha: 1)])!
        .draw(in: shape, angle: -70)
    // Soft top highlight, glass feel.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: tile.insetBy(dx: 18 * s, dy: 18 * s), xRadius: 168 * s, yRadius: 168 * s), angle: -90)

    func symbol(_ name: String, points: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: points, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }

    let phones = symbol("headphones", points: 400 * s, weight: .medium, color: .white)
    let p = phones.size
    phones.draw(in: NSRect(x: 512 * s - p.width / 2, y: 520 * s - p.height / 2, width: p.width, height: p.height))

    // Lock badge, bottom right.
    let badge = NSRect(x: 600 * s, y: 170 * s, width: 250 * s, height: 250 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge).fill()
    NSGraphicsContext.restoreGraphicsState()
    let lock = symbol("lock.fill", points: 120 * s, weight: .semibold, color: NSColor(red: 0.07, green: 0.33, blue: 0.86, alpha: 1))
    let l = lock.size
    lock.draw(in: NSRect(x: badge.midX - l.width / 2, y: badge.midY - l.height / 2, width: l.width, height: l.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
