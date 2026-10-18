// SPDX-License-Identifier: GPL-3.0-or-later
// Original geometric artwork for Specchio Studio. No external image or font.
// Run from the repository root: swift scripts/generate_icon.swift
import AppKit

func plane(_ points: [NSPoint], colors: [NSColor]) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    NSGradient(colors: colors)!.draw(in: path, angle: 45)
    NSColor.white.withAlphaComponent(0.22).setStroke()
    path.lineWidth = 3
    path.stroke()
}

func render(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 218, yRadius: 218)
    NSGradient(colors: [NSColor(srgbRed: 0.04, green: 0.07, blue: 0.16, alpha: 1),
                        NSColor(srgbRed: 0.12, green: 0.20, blue: 0.30, alpha: 1)])!.draw(in: background, angle: 60)
    // Two facing mirror planes; the offset light band connects their reflections.
    plane([NSPoint(x: 220, y: 290), NSPoint(x: 442, y: 394), NSPoint(x: 442, y: 782), NSPoint(x: 220, y: 678)],
          colors: [NSColor(srgbRed: 0.08, green: 0.56, blue: 0.62, alpha: 1),
                   NSColor(srgbRed: 0.49, green: 0.96, blue: 0.83, alpha: 1)])
    plane([NSPoint(x: 582, y: 242), NSPoint(x: 804, y: 346), NSPoint(x: 804, y: 734), NSPoint(x: 582, y: 630)],
          colors: [NSColor(srgbRed: 0.33, green: 0.29, blue: 0.79, alpha: 1),
                   NSColor(srgbRed: 0.69, green: 0.67, blue: 1, alpha: 1)])
    let light = NSBezierPath()
    light.move(to: NSPoint(x: 318, y: 548))
    light.line(to: NSPoint(x: 442, y: 488))
    light.line(to: NSPoint(x: 582, y: 548))
    light.line(to: NSPoint(x: 706, y: 488))
    light.lineWidth = 18
    light.lineCapStyle = .round
    light.lineJoinStyle = .round
    NSColor(srgbRed: 0.9, green: 1, blue: 0.99, alpha: 1).setStroke()
    light.stroke()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try render(pixels: size * scale).write(to: file)
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated original Specchio Studio icon and PNG sizes.")
