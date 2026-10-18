import SwiftUI
import AppKit
import Vision

enum PrivacyTests {
    private enum Failure: Error { case check(String) }

    @MainActor static func run(directory: URL) async throws {
        try checkSanitization()
        try checkRasterRedaction(directory: directory)
        try await checkOCRRedaction(directory: directory)
        print("PASS: privacy mask clamping, opaque pixels, source orientation, alpha and local OCR redaction")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.check(message) }
    }

    private static func checkSanitization() throws {
        let partial = PrivacyMask(rect: CGRect(x: -0.25, y: -0.5, width: 0.5, height: 0.75))
        try require(partial.rect == CGRect(x: 0, y: 0, width: 0.25, height: 0.25), "Mask was not clipped to the source")
        try require(!PrivacyMask(rect: CGRect(x: 1.1, y: 0, width: 0.3, height: 0.2)).isUsable,
                    "An outside mask remained usable")
        try require(!PrivacyMask(rect: CGRect(x: 0, y: 0, width: 0, height: 0.2)).isUsable,
                    "A zero-width mask remained usable")
        try require(!PrivacyMask(rect: CGRect(x: CGFloat.nan, y: 0, width: 0.2, height: 0.2)).isUsable,
                    "A nonfinite mask remained usable")
        try require(!PrivacyMask(rect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 0.2)).isUsable,
                    "An infinite mask remained usable")
        var mutable = PrivacyMask(rect: .zero)
        mutable.rect = CGRect(x: 0.75, y: 0.75, width: 0.5, height: 0.5)
        try require(mutable.rect == CGRect(x: 0.75, y: 0.75, width: 0.25, height: 0.25),
                    "Mask mutation bypassed clamping")
        let data = try JSONEncoder().encode(mutable)
        let decoded = try JSONDecoder().decode(PrivacyMask.self, from: data)
        try require(decoded == mutable, "Mask serialization changed its coordinates")
    }

    @MainActor private static func checkRasterRedaction(directory: URL) throws {
        let width = 64
        let height = 48
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: width * 4, bitsPerPixel: 32) else {
            throw Failure.check("Cannot create privacy raster fixture")
        }
        for y in 0..<height {
            for x in 0..<width {
                let color: NSColor
                if x >= 50 && y >= 36 { color = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0.25) }
                else if y < height / 2 {
                    color = NSColor(deviceRed: x < width / 2 ? 0 : 1,
                                    green: x < width / 2 ? 1 : 0, blue: 0, alpha: 1)
                } else {
                    color = NSColor(deviceRed: x < width / 2 ? 0 : 1,
                                    green: x < width / 2 ? 0 : 1, blue: 1, alpha: 1)
                }
                bitmap.setColor(color, atX: x, y: y)
            }
        }
        guard let sourceCG = bitmap.cgImage else { throw Failure.check("Cannot create source image") }
        let source = NSImage(cgImage: sourceCG, size: CGSize(width: 32, height: 24))
        let masks = [PrivacyMask(rect: CGRect(x: 0.125, y: 0.25, width: 0.375, height: 0.25)),
                     PrivacyMask(rect: CGRect(x: -0.08, y: 0.94, width: 0.16, height: 0.2)),
                     PrivacyMask(rect: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))]
        guard let output = PrivacyRenderer.redactedImage(source, masks: masks) else {
            throw Failure.check("Privacy rendering failed")
        }
        // Reuse similarly sized allocations before inspecting the returned image. Its pixels
        // must remain owned by the result after the renderer's scratch storage has been freed.
        let memoryChurn = (1...16).map { Data(repeating: UInt8($0 * 13), count: width * height * 4) }
        defer { withExtendedLifetime(memoryChurn) {} }
        guard let outputCG = PrivacyRenderer.sourceCGImage(output),
              let referenceCG = PrivacyRenderer.sourceCGImage(source) else {
            throw Failure.check("Privacy rendering failed")
        }
        try require(output.size == source.size && outputCG.width == width && outputCG.height == height,
                    "Privacy rendering changed pixel or point dimensions")
        let actual = NSBitmapImageRep(cgImage: outputCG)
        let reference = NSBitmapImageRep(cgImage: referenceCG)
        for y in 0..<height {
            for x in 0..<width {
                let covered = masks.filter(\.isUsable).contains { mask in
                    x >= Int(floor(mask.rect.minX * CGFloat(width))) &&
                        x < Int(ceil(mask.rect.maxX * CGFloat(width))) &&
                        y >= Int(floor(mask.rect.minY * CGFloat(height))) &&
                        y < Int(ceil(mask.rect.maxY * CGFloat(height)))
                }
                guard let color = actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let original = reference.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    throw Failure.check("Cannot sample privacy pixels")
                }
                if covered {
                    try require(color.redComponent == 0 && color.greenComponent == 0 &&
                                color.blueComponent == 0 && color.alphaComponent == 1,
                                "A masked pixel was not opaque black")
                } else {
                    let tolerance: CGFloat = 1.5 / 255
                    try require(abs(color.redComponent - original.redComponent) < tolerance &&
                                abs(color.greenComponent - original.greenComponent) < tolerance &&
                                abs(color.blueComponent - original.blueComponent) < tolerance &&
                                abs(color.alphaComponent - original.alphaComponent) < tolerance,
                                "Privacy rendering changed an uncovered pixel or its orientation")
                }
            }
        }
        guard let png = actual.representation(using: .png, properties: [:]) else {
            throw Failure.check("Cannot encode redacted fixture")
        }
        try png.write(to: directory.appendingPathComponent("privacy-redacted-pixels.png"))
    }

    @MainActor private static func checkOCRRedaction(directory: URL) async throws {
        let source = NSImage(size: CGSize(width: 1200, height: 360))
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 360).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 46, weight: .regular),
                                                       .foregroundColor: NSColor.black]
        ("Contact: test.person@example.com" as NSString).draw(at: CGPoint(x: 44, y: 230), withAttributes: attributes)
        ("Visible heading" as NSString).draw(at: CGPoint(x: 44, y: 70), withAttributes: attributes)
        source.unlockFocus()
        let suggestions = try await PrivacyScanner.scan(source)
        let emailMasks = suggestions.filter { $0.kind == .email }.map(\.mask)
        try require(!emailMasks.isEmpty, "Local OCR did not suggest a test email mask")
        guard let redacted = PrivacyRenderer.redactedImage(source, masks: emailMasks),
              let cgImage = PrivacyRenderer.sourceCGImage(redacted),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw Failure.check("Cannot encode OCR redaction export")
        }
        try png.write(to: directory.appendingPathComponent("privacy-redacted-ocr.png"))
        let request = PrivacyScanner.localTextRequest()
        try VNImageRequestHandler(data: png).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        try require(!text.lowercased().contains("example.com") && !text.lowercased().contains("test.person"),
                    "A redacted export still exposed the test email to OCR")
        try require(text.contains("Visible heading"), "Redaction removed unrelated source text")
        let after = try await PrivacyScanner.scan(redacted)
        try require(!after.contains { $0.kind == .email }, "The exported email remained recognizable")
    }
}
