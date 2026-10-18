import AppKit
@preconcurrency import AVFoundation
import CoreVideo

enum CreatorExportTests {
    private enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    @MainActor static func run(source: URL, directory: URL) async throws {
        let workspace = directory.appendingPathComponent("creator-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let exporter = CreatorExport()
        let asset = AVURLAsset(url: source)
        let sourceDuration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio).count
        let start = min(0.1, sourceDuration / 4)
        let end = min(sourceDuration, start + 0.25)
        let masks = [PrivacyMask(rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
        let package = try await exporter.exportVideo(source: source, directory: workspace, backdrop: .paper,
            showFrame: true, quarterTurns: 1, flipped: true, trimStart: start, trimEnd: end,
            privacyMasks: masks, coverTitle: "Creator test")
        let names = ["portrait-9x16.mov", "square-1x1.mov", "landscape-16x9.mov"]
        let sizes = [CGSize(width:1080,height:1920), CGSize(width:1080,height:1080), CGSize(width:1920,height:1080)]
        for (name, size) in zip(names, sizes) {
            let result = AVURLAsset(url: package.appendingPathComponent(name))
            guard let track = try await result.loadTracks(withMediaType: .video).first else { throw Failure.message("Creator: video track missing.") }
            let outputSize = try await track.load(.naturalSize)
            let seconds = try await result.load(.duration).seconds
            let audio = try await result.loadTracks(withMediaType: .audio).count
            guard outputSize == size, abs(seconds - (end - start)) < 0.06, audio == audioTracks else {
                throw Failure.message("Creator: wrong dimensions, trim or audio for \(name).")
            }
            let frame = try await bitmap(asset: result, seconds: 0.1)
            try assertBlack(frame, x: Int(size.width/2), y: Int(size.height/2), context: name)
        }
        guard let cover = NSImage(contentsOf: package.appendingPathComponent("cover.png")),
              let tiff = cover.tiffRepresentation, let coverBitmap = NSBitmapImageRep(data: tiff),
              coverBitmap.pixelsWide == 1920, coverBitmap.pixelsHigh == 1080 else {
            throw Failure.message("Creator: cover missing or wrong dimensions.")
        }
        try assertBlack(coverBitmap, x: 960, y: 540, context: "cover")
        let manifestData = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let outputs = manifest["outputs"] as? [[String: Any]], outputs.count == 4,
              manifest["privacyMaskCount"] as? Int == 1,
              !(String(data: manifestData, encoding: .utf8) ?? "").contains(source.path) else {
            throw Failure.message("Creator: manifest is incomplete or exposes the source path.")
        }
        let secondPackage = try await exporter.exportImages(image: cover, directory: workspace, backdrop: .paper,
            showFrame: false, quarterTurns: 0, flipped: false, zoom: 1, marks: [], privacyMasks: [], coverTitle: "Image set")
        guard secondPackage != package else { throw Failure.message("Creator: existing package overwritten.") }
        for (name, size) in zip(["portrait-9x16.png", "square-1x1.png", "landscape-16x9.png"], sizes) {
            guard let image = NSImage(contentsOf: secondPackage.appendingPathComponent(name)),
                  let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  bitmap.pixelsWide == Int(size.width), bitmap.pixelsHigh == Int(size.height) else {
                throw Failure.message("Creator: image rendition is missing or wrong size.")
            }
        }

        let before = try Set(FileManager.default.contentsOfDirectory(atPath: workspace.path))
        let cancellation = Task { try await exporter.exportVideo(source: source, directory: workspace,
            backdrop: .aurora, showFrame: true, quarterTurns: 0, flipped: false) }
        await Task.yield()
        exporter.cancel()
        do { _ = try await cancellation.value; throw Failure.message("Creator: cancelled export succeeded.") }
        catch is CancellationError { }
        guard !exporter.isExporting, try Set(FileManager.default.contentsOfDirectory(atPath: workspace.path)) == before else {
            throw Failure.message("Creator: cancellation left partial package files.")
        }
        var failedAsExpected = false
        do {
            _ = try await exporter.exportVideo(source: workspace.appendingPathComponent("missing-source.mov"), directory: workspace,
                backdrop: .paper, showFrame: false, quarterTurns: 0, flipped: false)
        } catch { failedAsExpected = true }
        guard failedAsExpected, !exporter.isExporting,
              try Set(FileManager.default.contentsOfDirectory(atPath: workspace.path)) == before else {
            throw Failure.message("Creator: failed export left partial package files.")
        }

        let orientedSource = workspace.appendingPathComponent("orientation-source.mov")
        try await makeWhiteClip(at: orientedSource)
        let videoExporter = VideoExporter()
        let partialMask = [PrivacyMask(rect: CGRect(x: 0.125, y: 0.2, width: 0.25, height: 0.4))]
        // Preferred transform is 90°. Expected centres below independently cover
        // metadata orientation, each quarter turn, and horizontal mirroring.
        let cases: [(Int, Bool, CGPoint, CGPoint)] = [
            (0, false, CGPoint(x:72,y:52), CGPoint(x:62,y:92)),
            (1, true, CGPoint(x:52,y:72), CGPoint(x:92,y:62)),
            (2, true, CGPoint(x:72,y:132), CGPoint(x:62,y:92)),
            (3, true, CGPoint(x:132,y:52), CGPoint(x:92,y:62))
        ]
        for (turns, flipped, redacted, untouched) in cases {
            let url = workspace.appendingPathComponent("privacy-turn-\(turns).mov")
            try await videoExporter.export(source: orientedSource, destination: url, backdrop: .paper, showFrame: false,
                quarterTurns: turns, flipped: flipped, trimStart: 0.05, trimEnd: 0.3, privacyMasks: partialMask)
            for time in [0.02, 0.12, 0.21] {
                let frame = try await bitmap(asset: AVURLAsset(url: url), seconds: time)
                try assertBlack(frame, x: Int(redacted.x), y: Int(redacted.y), context: "rotated mask \(turns) at \(time)")
                guard let color = frame.colorAt(x: Int(untouched.x), y: Int(untouched.y))?.usingColorSpace(.deviceRGB),
                      min(color.redComponent, color.greenComponent, color.blueComponent) > 0.85 else {
                    throw Failure.message("Creator: mask covered the wrong source region for turn \(turns).")
                }
            }
        }
        print("PASS: creator 3-video and 3-image packages, cover, manifest, audio, trim, unique directories, cancellation/failure cleanup; burned privacy across metadata orientation, four turns, mirroring and whole clip")
    }

    private static func bitmap(asset: AVAsset, seconds: Double) async throws -> NSBitmapImageRep {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return NSBitmapImageRep(cgImage: result.image)
    }
    private static func assertBlack(_ bitmap: NSBitmapImageRep, x: Int, y: Int, context: String) throws {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              max(color.redComponent, color.greenComponent, color.blueComponent) < 0.08 else {
            throw Failure.message("Creator: private pixels visible in \(context) at \(x),\(y).")
        }
    }
    private static func makeWhiteClip(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 100])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 100, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 100,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.message("Creator: fixture writer failed.") }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<12 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? Failure.message("Creator: fixture writer stopped.") }
                try await Task.sleep(for: .milliseconds(2))
            }
            var pixel: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel) == kCVReturnSuccess,
                  let pixel else { throw Failure.message("Creator: fixture buffer failed.") }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) { memset(base, 255, CVPixelBufferGetBytesPerRow(pixel) * 100) }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? Failure.message("Creator: fixture append failed.")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.message("Creator: fixture did not finish.") }
    }
}
