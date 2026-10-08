// Draws the app icon (Magno green squircle + gold emblem + orange "open loop" dot) and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (run from the project root)
import AppKit

let emblemURL = URL(fileURLWithPath: "Resources/brand/emblem-gold.png")
let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
let outputURL = URL(fileURLWithPath: "Resources/AppIcon.icns")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// Apple's macOS icon grid: an 824pt rounded square centered on a 1024pt canvas.
func drawBackground(in context: CGContext) -> CGRect {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x183029))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [color(0x24463C), color(0x183029), color(0x0F211C)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.addPath(CGPath(roundedRect: body.insetBy(dx: 6, dy: 6), cornerWidth: 180, cornerHeight: 180, transform: nil))
    context.setStrokeColor(color(0xD2BC86, alpha: 0.28))
    context.setLineWidth(5)
    context.strokePath()
    return body
}

func drawEmblem(in context: CGContext, body: CGRect) {
    guard let emblem = NSImage(contentsOf: emblemURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("emblem not found at \(emblemURL.path)")
    }
    let height: CGFloat = 540
    let width = height * CGFloat(emblem.width) / CGFloat(emblem.height)
    let frame = CGRect(x: body.midX - width / 2, y: body.midY - height / 2 - 6, width: width, height: height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x000000, alpha: 0.35))
    context.draw(emblem, in: frame)
    context.restoreGState()
}

func drawOpenLoopDot(in context: CGContext, body: CGRect) {
    let radius: CGFloat = 58
    let center = CGPoint(x: body.maxX - 150, y: body.maxY - 150)
    let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.setFillColor(color(0x183029))
    context.fillEllipse(in: dot.insetBy(dx: -14, dy: -14))
    context.setFillColor(color(0xE8913A))
    context.fillEllipse(in: dot)
}

func renderIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let body = drawBackground(in: context)
    drawEmblem(in: context, body: body)
    drawOpenLoopDot(in: context, body: body)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try renderIcon(size: base).write(to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderIcon(size: base * 2).write(to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try renderIcon(size: 1024).write(to: URL(fileURLWithPath: "build/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "OK: \(outputURL.path)" : "iconutil failed")
