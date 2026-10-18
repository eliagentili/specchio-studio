// SPDX-License-Identifier: GPL-3.0-or-later
// Original code-native artwork using the project's existing generated demo.
// Run from repository root: swift scripts/generate_marketing_assets.swift
// Regenerate demo exports from application source first: add --render-demo.
// --render-demo requires native build artifacts from ./build.sh.
import AppKit
import CryptoKit

let files = FileManager.default
let root = URL(fileURLWithPath: files.currentDirectoryPath, isDirectory: true)
let destination = root.appendingPathComponent("docs/assets", isDirectory: true)
try files.createDirectory(at: destination, withIntermediateDirectories: true)

@discardableResult
func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "MarketingAssets", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(executable) failed"])
    }
    return process.terminationStatus
}

if CommandLine.arguments.contains("--render-demo") {
    let sources = try files.contentsOfDirectory(atPath: root.appendingPathComponent("Sources").path)
        .filter { $0.hasSuffix(".swift") }.sorted().map { "Sources/" + $0 }
    let frameworks = ["SwiftUI", "AppKit", "AVFoundation", "CoreMediaIO", "CoreImage",
                      "ScreenCaptureKit", "Vision", "VideoToolbox", "AudioToolbox", "Security"]
    try run("/usr/bin/xcrun", ["swiftc", "-D", "STUDIO_TEST", "-swift-version", "5",
        "-parse-as-library", "-target", "arm64-apple-macos14.0", "-module-cache-path", ".build/cache",
        "-import-objc-header", "Native/WirelessBridge.h"] + sources +
        ["scripts/render_marketing_demo.swift", "-o", ".build/MarketingDemoRenderer"] +
        frameworks.flatMap { ["-framework", $0] } +
        [".build/native/libSpecchioAirPlay.a", "ThirdParty/OpenSSL/lib/libcrypto.a", "-lz"])
    try run(root.appendingPathComponent(".build/MarketingDemoRenderer").path, [destination.path])
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let navy = color(0x0B1923), mint = color(0xA5F3D7), muted = color(0xB3C4CD)

func text(_ string: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color foreground: NSColor = .white, alignment: NSTextAlignment = .left,
          lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight }
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: foreground,
        .paragraphStyle: paragraph
    ]).draw(in: rect)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func image(_ file: String, in rect: NSRect, radius: CGFloat = 0) throws {
    let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : root.appendingPathComponent(file)
    guard let source = NSImage(contentsOf: url) else {
        throw NSError(domain: "MarketingAssets", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing image: \(url.path)"])
    }
    let scale = min(rect.width / source.size.width, rect.height / source.size.height)
    let target = NSRect(x: rect.midX - source.size.width * scale / 2,
                        y: rect.midY - source.size.height * scale / 2,
                        width: source.size.width * scale, height: source.size.height * scale)
    NSGraphicsContext.saveGraphicsState()
    if radius > 0 { NSBezierPath(roundedRect: target, xRadius: radius, yRadius: radius).addClip() }
    source.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ name: String, width: Int, height: Int, draw: () throws -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    try draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try data.write(to: destination.appendingPathComponent(name))
}

func socialCard(_ name: String) throws {
try render(name, width: 1200, height: 630) {
    navy.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
    // An original geometric accent; no device or application interface is invented.
    let plane = NSBezierPath()
    plane.move(to: NSPoint(x: 670, y: 0)); plane.line(to: NSPoint(x: 1200, y: 0))
    plane.line(to: NSPoint(x: 1200, y: 630)); plane.line(to: NSPoint(x: 880, y: 630)); plane.close()
    NSGradient(colors: [color(0x183142), color(0x11392F)])!.draw(in: plane, angle: 40)
    try image("Resources/AppIcon.iconset/icon_128x128.png", in: NSRect(x: 62, y: 512, width: 55, height: 55))
    text("Specchio Studio", rect: NSRect(x: 132, y: 519, width: 440, height: 40), size: 27, weight: .semibold)
    text("Your device.\nReady to share.",
         rect: NSRect(x: 70, y: 298, width: 660, height: 168),
         size: 61, weight: .bold, lineHeight: 72)
    text("Demo. Explain. Create.",
         rect: NSRect(x: 73, y: 250, width: 610, height: 40), size: 28, color: muted)
    rounded(NSRect(x: 73, y: 195, width: 241, height: 33), radius: 16, fill: mint)
    text("macOS · Local processing",
         rect: NSRect(x: 88, y: 201, width: 213, height: 22),
         size: 15, weight: .medium, color: navy)
    text("Created by Elia Gentili",
         rect: NSRect(x: 73, y: 76, width: 580, height: 30),
         size: 21, weight: .medium, color: mint)
    text("A focused workflow for demos and bug reports.",
         rect: NSRect(x: 73, y: 45, width: 610, height: 27),
         size: 16, color: muted)
    try image("Anteprima-demo.png", in: NSRect(x: 755, y: 55, width: 370, height: 520), radius: 22)
}
}
try socialCard("social-card.png")
try Data(contentsOf: destination.appendingPathComponent("social-card.png"))
    .write(to: destination.appendingPathComponent("github-banner.png"))
try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.iconset/icon_256x256.png"))
    .write(to: destination.appendingPathComponent("app-icon.png"))

try render("formats-proof.png", width: 1440, height: 840) {
    color(0xF3F6F2).setFill(); NSRect(x: 0, y: 0, width: 1440, height: 840).fill()
    text("One composition. Three formats.", rect: NSRect(x: 64, y: 736, width: 1312, height: 56),
         size: 38, weight: .bold, color: navy)
    text("Actual demo canvas renders · Specchio Studio", rect: NSRect(x: 65, y: 697, width: 1310, height: 31),
         size: 19, color: color(0x52666C))
    for (file, box, title, subtitle) in [
        ("format-portrait.png", NSRect(x: 65, y: 100, width: 281, height: 560), "9:16", "Portrait"),
        ("format-square.png", NSRect(x: 406, y: 100, width: 376, height: 560), "1:1", "Square"),
        ("format-landscape.png", NSRect(x: 842, y: 100, width: 533, height: 560), "16:9", "Landscape")
    ] {
        try image(destination.appendingPathComponent(file).path, in: box, radius: 11)
        text(title, rect: NSRect(x: box.minX, y: 55, width: box.width, height: 34), size: 24,
             weight: .bold, color: navy, alignment: .center)
        text(subtitle, rect: NSRect(x: box.minX, y: 27, width: box.width, height: 25), size: 16,
             color: color(0x52666C), alignment: .center)
    }
}

let favicon = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect x="1" y="1" width="62" height="62" rx="14" fill="#0b1923"/>
  <path d="M14 43V18l14-7v25z" fill="#7df5d4"/>
  <path d="M36 49V24l14-7v25z" fill="#aaaaff"/>
  <path d="m20 29 8 4 8-4 8 4" fill="none" stroke="#e6fffc" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""
try favicon.write(to: destination.appendingPathComponent("favicon.svg"), atomically: true, encoding: .utf8)

let encoderPaths = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp", "/usr/bin/cwebp"]
guard let encoder = encoderPaths.first(where: { files.isExecutableFile(atPath: $0) }) else {
    fatalError("Install cwebp to create the optimized demo-preview.webp asset.")
}
try run(encoder, ["-quiet", "-q", "86", "-m", "6", "-metadata", "none",
                  "Anteprima-demo.png", "-o", destination.appendingPathComponent("demo-preview.webp").path])
try run(encoder, ["-quiet", "-q", "86", "-m", "6", "-metadata", "none",
                  destination.appendingPathComponent("formats-proof.png").path,
                  "-o", destination.appendingPathComponent("formats-proof.webp").path])

let descriptions = [
    "social-card.png": "Specchio Studio: Your device. Ready to share. Created by Elia Gentili, beside the actual generated demo composition.",
    "github-banner.png": "Specchio Studio by Elia Gentili. A local macOS workflow for demos, explanations and bug reports, with an actual demo composition.",
    "demo-preview.webp": "Actual Specchio Studio demo composition: a framed display with MAKE ROOM artwork on the Aurora background. No physical device is connected.",
    "app-icon.png": "Specchio Studio icon: mint and lavender mirror planes on a dark navy background.",
    "favicon.svg": "Simplified original Specchio Studio mirror icon.",
    "formats-proof.png": "The actual generated demo composition rendered by StudioCanvas in portrait 9:16, square 1:1 and landscape 16:9 formats.",
    "formats-proof.webp": "The actual generated demo composition rendered by StudioCanvas in portrait 9:16, square 1:1 and landscape 16:9 formats.",
    "format-portrait.png": "Actual portrait 9:16 demo composition rendered by StudioCanvas.",
    "format-square.png": "Actual square 1:1 demo composition rendered by StudioCanvas.",
    "format-landscape.png": "Actual landscape 16:9 demo composition rendered by StudioCanvas."
]
var assets: [[String: Any]] = []
for name in descriptions.keys.sorted() {
    let data = try Data(contentsOf: destination.appendingPathComponent(name))
    assets.append(["file": name, "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                   "alt": descriptions[name]!])
}
let manifest: [String: Any] = [
    "schemaVersion": 1, "creator": "Elia Gentili", "license": "GPL-3.0-or-later",
    "externalImages": false, "externalFonts": false, "generatedInterfaceMockups": false,
    "sourceArtwork": ["Anteprima-demo.png", "scripts/generate_icon.swift", "Sources/Canvas.swift"],
    "notes": ["Demo artwork is generated by the application; it is not a physical-device capture or a full application screenshot.",
              "Format source PNGs are rendered from the actual StudioCanvas at half its export pixel dimensions; their complete composition remains visible.",
              "Social artwork uses AppKit system fonts at generation time. It does not embed or distribute font files.",
              "No performance, availability, compatibility or exclusivity claim is inferred by these illustrations."],
    "regenerate": "swift scripts/generate_marketing_assets.swift --render-demo",
    "assets": assets
]
let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: destination.appendingPathComponent("provenance.json"))
print("Generated marketing assets in docs/assets.")
