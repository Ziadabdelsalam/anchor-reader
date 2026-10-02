// Renders the app icon (lines of text with one in the spotlight) into an .iconset folder.
// Usage: swift Tools/make_icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: content inset ~10%
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    color(0xFBF8F1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let w = tile.width
    func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ c: NSColor) {
        let r = NSRect(x: tile.minX + x * w, y: tile.minY + y * w, width: width * w, height: height * w)
        c.setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }
    // Spotlight band behind the current line
    let band = NSRect(x: tile.minX + 0.12 * w, y: tile.minY + 0.39 * w, width: 0.76 * w, height: 0.22 * w)
    color(0xF1E3C6).setFill()
    NSBezierPath(roundedRect: band, xRadius: 0.06 * w, yRadius: 0.06 * w).fill()

    bar(0.22, 0.70, 0.56, 0.075, color(0x1E1C19, 0.18))
    bar(0.22, 0.4625, 0.58, 0.075, color(0x1E1C19))
    bar(0.15, 0.42, 0.035, 0.16, color(0xC8742A))
    bar(0.22, 0.225, 0.44, 0.075, color(0x1E1C19, 0.18))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try! render(px).write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
print("Wrote \(output)")
