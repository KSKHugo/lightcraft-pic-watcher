// Draws the app icon and writes AppPackaging/AppIcon.icns.
//
//   swift Scripts/make_icon.swift
//
// The icon is vector drawing, rendered separately for every size the icon set needs, so the
// small sizes stay sharp instead of being scaled down from one bitmap. It follows the macOS
// icon grid: a 824 pt squircle centred on a 1024 pt canvas. Motif: a photo print with a round
// badge holding a download arrow, as in the menu bar symbol. Deliberately no LightCraft marks.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
let output = root.appendingPathComponent("AppPackaging/AppIcon.icns")
let preview = root.appendingPathComponent("AppPackaging/AppIcon-1024.png")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// The icon tile: a rounded square with the corner radius of the macOS grid (185 of 824).
func squircle(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
}

/// The download arrow inside the badge, centred on `c`.
func arrowPath(_ c: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.addRoundedRect(in: CGRect(x: c.x - 22, y: c.y - 82, width: 44, height: 100), cornerWidth: 12, cornerHeight: 12)
    path.move(to: CGPoint(x: c.x - 70, y: c.y - 2))
    path.addLine(to: CGPoint(x: c.x + 70, y: c.y - 2))
    path.addLine(to: CGPoint(x: c.x, y: c.y + 68))
    path.closeSubpath()
    path.addRoundedRect(in: CGRect(x: c.x - 84, y: c.y + 80, width: 168, height: 26), cornerWidth: 13, cornerHeight: 13)
    return path
}

func draw(in context: CGContext) {
    // Top-left origin, like the coordinates above.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let outline = squircle(body)

    // Drop shadow of the whole tile, as on the macOS grid.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x000000, 0.30))
    context.addPath(outline)
    context.setFillColor(color(0x5A2410))
    context.fillPath()
    context.restoreGState()

    // Warm background, the app's accent colour.
    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.drawLinearGradient(gradient([color(0xE98A55), color(0xB04E1C), color(0x5E2614)], [0, 0.55, 1]),
                               start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.drawRadialGradient(gradient([color(0xFFFFFF, 0.25), color(0xFFFFFF, 0)], [0, 1]),
                               startCenter: CGPoint(x: 512, y: 160), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 160), endRadius: 520, options: [])

    // Photo print, slightly tilted.
    context.saveGState()
    context.translateBy(x: 470, y: 480)
    context.rotate(by: -6 * .pi / 180)
    let card = CGRect(x: -250, y: -190, width: 500, height: 380)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 20), blur: 40, color: color(0x2A0E04, 0.45))
    context.addPath(CGPath(roundedRect: card, cornerWidth: 30, cornerHeight: 30, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    let picture = card.insetBy(dx: 26, dy: 26)
    context.saveGState()
    context.addPath(CGPath(roundedRect: picture, cornerWidth: 12, cornerHeight: 12, transform: nil))
    context.clip()
    context.drawLinearGradient(gradient([color(0x9FD3F5), color(0xF6D9A8), color(0xF2A46B)], [0, 0.6, 1]),
                               start: CGPoint(x: 0, y: picture.minY), end: CGPoint(x: 0, y: picture.maxY), options: [])
    context.setFillColor(color(0xFFF6DC))
    context.fillEllipse(in: CGRect(x: 70, y: -120, width: 96, height: 96))
    let far = CGMutablePath()
    far.move(to: CGPoint(x: picture.minX, y: 80))
    far.addLine(to: CGPoint(x: -120, y: -50))
    far.addLine(to: CGPoint(x: -20, y: 40))
    far.addLine(to: CGPoint(x: 80, y: -30))
    far.addLine(to: CGPoint(x: picture.maxX, y: 90))
    far.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
    far.addLine(to: CGPoint(x: picture.minX, y: picture.maxY))
    far.closeSubpath()
    context.addPath(far)
    context.setFillColor(color(0x6E8A5A))
    context.fillPath()
    let near = CGMutablePath()
    near.move(to: CGPoint(x: picture.minX, y: 130))
    near.addLine(to: CGPoint(x: -50, y: 60))
    near.addLine(to: CGPoint(x: 70, y: 130))
    near.addLine(to: CGPoint(x: 150, y: 85))
    near.addLine(to: CGPoint(x: picture.maxX, y: 140))
    near.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
    near.addLine(to: CGPoint(x: picture.minX, y: picture.maxY))
    near.closeSubpath()
    context.addPath(near)
    context.setFillColor(color(0x3E5A3A))
    context.fillPath()
    context.restoreGState()
    context.restoreGState()

    // Badge with the download arrow, lower right.
    let c = CGPoint(x: 680, y: 690)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x2A0E04, 0.45))
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: c.x - 150, y: c.y - 150, width: 300, height: 300))
    context.restoreGState()
    context.addPath(arrowPath(c))
    context.setFillColor(color(0xB04E1C))
    context.fillPath()

    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try render(pixels: 1024).write(to: preview)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
