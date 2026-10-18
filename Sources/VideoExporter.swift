import AppKit
@preconcurrency import AVFoundation
import Combine
import QuartzCore

private enum VideoExportFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Decorated, opaque H.264 movie export; capture files themselves stay untouched.
@MainActor
final class VideoExporter: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var errorMessage: String?
    private var session: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?
    private var cancellationRequested = false

    func cancel() {
        cancellationRequested = true
        session?.cancelExport()
    }

    /// trimStart/trimEnd are seconds in the original asset. Nil means its beginning/end.
    /// `.transparent` intentionally becomes opaque black because H.264 has no alpha channel.
    func export(source: URL, destination: URL, backdrop: Backdrop, showFrame: Bool,
                quarterTurns: Int, flipped: Bool, trimStart: Double? = nil, trimEnd: Double? = nil,
                format: CompositionFormat = .adaptive, privacyMasks: [PrivacyMask] = []) async throws {
        guard !isExporting else { throw VideoExportFailure.message(L("Un'esportazione è già in corso.")) }
        isExporting = true
        progress = 0
        errorMessage = nil
        cancellationRequested = false
        var mayHaveCreatedDestination = false
        var succeeded = false
        defer {
            progressTask?.cancel()
            progressTask = nil
            session = nil
            isExporting = false
            if mayHaveCreatedDestination && !succeeded { try? FileManager.default.removeItem(at: destination) }
        }
        do {
            guard source.standardizedFileURL != destination.standardizedFileURL else {
                throw VideoExportFailure.message(L("Scegli un file diverso dall'originale."))
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw VideoExportFailure.message(L("Il file di destinazione esiste già. Scegli un nuovo nome."))
            }
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideo = videoTracks.first else { throw VideoExportFailure.message(L("Il file non contiene una traccia video.")) }
            let naturalSize = try await sourceVideo.load(.naturalSize)
            let preferredTransform = try await sourceVideo.load(.preferredTransform)
            let sourceVideoRange = try await sourceVideo.load(.timeRange)
            let nominalFPS = try await sourceVideo.load(.nominalFrameRate)
            let assetSeconds = duration.seconds
            guard assetSeconds.isFinite, assetSeconds > 0,
                  naturalSize.width.isFinite, naturalSize.height.isFinite, naturalSize.width > 0, naturalSize.height > 0,
                  [preferredTransform.a, preferredTransform.b, preferredTransform.c, preferredTransform.d,
                   preferredTransform.tx, preferredTransform.ty].allSatisfy({ $0.isFinite }),
                  preferredTransform.a * preferredTransform.d - preferredTransform.b * preferredTransform.c != 0 else {
                throw VideoExportFailure.message(L("Durata o dimensioni del video non valide."))
            }
            let start = trimStart ?? 0
            let end = trimEnd ?? assetSeconds
            guard start.isFinite, end.isFinite, start >= 0, end <= assetSeconds + 0.001, end > start else {
                throw VideoExportFailure.message(L("Intervallo di taglio non valido."))
            }
            let requestedRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                             end: CMTime(seconds: min(end, assetSeconds), preferredTimescale: 600))
            let range = CMTimeRangeGetIntersection(requestedRange, otherRange: sourceVideoRange)
            guard range.isValid, !range.isEmpty, range.duration.seconds > 0 else {
                throw VideoExportFailure.message(L("L'intervallo selezionato non contiene video."))
            }
            try checkCancellation()
            let composition = AVMutableComposition()
            guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoExportFailure.message(L("Impossibile preparare la traccia video."))
            }
            try video.insertTimeRange(range, of: sourceVideo, at: .zero)
            video.preferredTransform = .identity
            // Preserve every source audio track and its offset relative to the selected video.
            for sourceAudio in try await asset.loadTracks(withMediaType: .audio) {
                let audioRange = try await sourceAudio.load(.timeRange)
                let intersection = CMTimeRangeGetIntersection(range, otherRange: audioRange)
                guard intersection.isValid, !intersection.isEmpty else { continue }
                guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw VideoExportFailure.message(L("Impossibile conservare una traccia audio."))
                }
                try audio.insertTimeRange(intersection, of: sourceAudio, at: CMTimeSubtract(intersection.start, range.start))
            }

            let geometry = Self.geometry(naturalSize: naturalSize, preferred: preferredTransform,
                                         quarterTurns: quarterTurns, flipped: flipped, showFrame: showFrame, format: format)
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = geometry.canvas
            let fps = nominalFPS.isFinite && nominalFPS > 0 ? min(60, Double(nominalFPS)) : 30
            videoComposition.frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 60000)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
            instruction.backgroundColor = NSColor.clear.cgColor
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            layerInstruction.setTransform(geometry.transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]
            videoComposition.animationTool = Self.animationTool(canvas: geometry.canvas, videoRect: geometry.videoRect,
                                                                backdrop: backdrop, showFrame: showFrame, border: geometry.border,
                                                                privacyRects: Self.privacyRects(privacyMasks, naturalSize: naturalSize,
                                                                                               transform: geometry.transform, canvas: geometry.canvas))
            try checkCancellation()
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality),
                  exporter.supportedFileTypes.contains(.mov) else {
                throw VideoExportFailure.message(L("Esportazione H.264 MOV non disponibile per questo video."))
            }
            exporter.outputURL = destination
            exporter.outputFileType = .mov
            exporter.videoComposition = videoComposition
            exporter.shouldOptimizeForNetworkUse = true
            session = exporter
            mayHaveCreatedDestination = true
            progressTask = Task { [weak self, weak exporter] in
                while !Task.isCancelled {
                    guard let self, let exporter else { return }
                    self.progress = Double(exporter.progress)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            try await withTaskCancellationHandler {
                try checkCancellation()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exporter.exportAsynchronously { continuation.resume() }
                }
            } onCancel: { exporter.cancelExport() }
            if exporter.status == .cancelled || cancellationRequested || Task.isCancelled { throw CancellationError() }
            guard exporter.status == .completed else {
                throw exporter.error ?? VideoExportFailure.message(L("Esportazione video non riuscita."))
            }
            succeeded = true
            progress = 1
        } catch {
            errorMessage = error is CancellationError ? L("Esportazione annullata.") : error.localizedDescription
            throw error
        }
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled { throw CancellationError() }
    }

    private struct Geometry {
        var canvas: CGSize
        var videoRect: CGRect
        var transform: CGAffineTransform
        var border: CGFloat
    }

    /// Normalize each operation's bounds so portrait metadata, rotation and mirroring never crop.
    private static func geometry(naturalSize: CGSize, preferred: CGAffineTransform, quarterTurns: Int,
                                 flipped: Bool, showFrame: Bool, format: CompositionFormat) -> Geometry {
        let sourceRect = CGRect(origin: .zero, size: naturalSize)
        let preferredBounds = sourceRect.applying(preferred).standardized
        var transform = preferred.concatenating(CGAffineTransform(translationX: -preferredBounds.minX, y: -preferredBounds.minY))
        let turns = ((quarterTurns % 4) + 4) % 4
        transform = transform.concatenating(CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2))
        var bounds = sourceRect.applying(transform).standardized
        transform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        bounds = sourceRect.applying(transform).standardized
        if flipped {
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: bounds.width, y: 0))
        }
        let shortSide = min(bounds.width, bounds.height)
        let border = showFrame ? shortSide * 0.025 : 0
        let padding = shortSide * 0.12
        let unscaledCanvas = CGSize(width: bounds.width + 2 * (border + padding), height: bounds.height + 2 * (border + padding))
        func even(_ value: CGFloat) -> CGFloat { max(2, floor(value / 2) * 2) }
        let scale: CGFloat
        let canvas: CGSize
        if let preset = format.exportSize {
            canvas = preset
            scale = min(preset.width / unscaledCanvas.width, preset.height / unscaledCanvas.height)
        } else {
            scale = min(1, 1920 / max(unscaledCanvas.width, unscaledCanvas.height))
            canvas = CGSize(width: even(unscaledCanvas.width * scale), height: even(unscaledCanvas.height * scale))
        }
        let videoSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let rect = CGRect(x: (canvas.width - videoSize.width) / 2, y: (canvas.height - videoSize.height) / 2,
                          width: videoSize.width, height: videoSize.height)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Geometry(canvas: canvas, videoRect: rect, transform: transform, border: border * scale)
    }

    private static func animationTool(canvas: CGSize, videoRect: CGRect, backdrop: Backdrop,
                                      showFrame: Bool, border: CGFloat, privacyRects: [CGRect]) -> AVVideoCompositionCoreAnimationTool {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let bounds = CGRect(origin: .zero, size: canvas)
        let parent = CALayer()
        parent.frame = bounds
        parent.isGeometryFlipped = false
        let background = CAGradientLayer()
        background.frame = bounds
        background.colors = gradientColors(backdrop)
        background.startPoint = CGPoint(x: 0, y: 1)
        background.endPoint = CGPoint(x: 1, y: 0)
        parent.addSublayer(background)
        let radius = showFrame ? min(videoRect.width, videoRect.height) * 0.065 : 0
        if showFrame {
            let frame = CALayer()
            frame.frame = videoRect.insetBy(dx: -border, dy: -border)
            frame.cornerRadius = radius + border
            frame.backgroundColor = NSColor(white: 0.075, alpha: 1).cgColor
            frame.borderColor = NSColor(white: 1, alpha: 0.30).cgColor
            frame.borderWidth = 1
            frame.shadowColor = NSColor.black.cgColor
            frame.shadowOpacity = 0.35
            frame.shadowOffset = CGSize(width: 0, height: -min(canvas.width, canvas.height) * 0.025)
            frame.shadowRadius = min(canvas.width, canvas.height) * 0.035
            parent.addSublayer(frame)
        }
        let video = CALayer()
        video.frame = bounds
        // Mask only the image area; the gradient and physical frame stay outside this mask.
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = CGPath(roundedRect: videoRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        mask.fillColor = NSColor.white.cgColor
        video.mask = mask
        parent.addSublayer(video)
        // The video transform uses top-left source coordinates; Core Animation is
        // bottom-left. Burn solid overlays after the video, for its entire duration.
        let redactions = CALayer()
        redactions.frame = bounds
        let redactionClip = CAShapeLayer()
        redactionClip.frame = bounds
        redactionClip.path = CGPath(roundedRect: videoRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        redactionClip.fillColor = NSColor.white.cgColor
        redactions.mask = redactionClip
        for rect in privacyRects {
            let redaction = CALayer()
            redaction.frame = rect
            redaction.backgroundColor = NSColor.black.cgColor
            redaction.opacity = 1
            redactions.addSublayer(redaction)
        }
        parent.addSublayer(redactions)
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
    }

    private static func privacyRects(_ masks: [PrivacyMask], naturalSize: CGSize,
                                     transform: CGAffineTransform, canvas: CGSize) -> [CGRect] {
        masks.compactMap { mask in
            let rect = mask.rect
            guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite) else { return nil }
            let clipped = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            let pixels = CGRect(x: clipped.minX * naturalSize.width, y: clipped.minY * naturalSize.height,
                                width: clipped.width * naturalSize.width, height: clipped.height * naturalSize.height)
            let mapped = pixels.applying(transform).standardized
            // Round outwards and cover compression/interpolation at the edges.
            return CGRect(x: floor(mapped.minX) - 2, y: floor(canvas.height - mapped.maxY) - 2,
                          width: ceil(mapped.maxX) - floor(mapped.minX) + 4,
                          height: ceil(mapped.maxY) - floor(mapped.minY) + 4)
        }
    }

    private static func gradientColors(_ backdrop: Backdrop) -> [CGColor] {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: 1).cgColor
        }
        switch backdrop {
        case .midnight: return [rgb(0.12, 0.14, 0.18), rgb(0.05, 0.06, 0.08)]
        case .aurora: return [rgb(0.17, 0.43, 0.38), rgb(0.14, 0.16, 0.31)]
        case .ocean: return [rgb(0.15, 0.35, 0.61), rgb(0.08, 0.14, 0.29)]
        case .paper: return [NSColor.white.cgColor, NSColor(white: 0.88, alpha: 1).cgColor]
        case .transparent: return [NSColor.black.cgColor, NSColor.black.cgColor]
        }
    }

    /// Tests a caller-provided synthetic clip. Does not request capture permissions.
    static func selfTest(source: URL, directory: URL) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceAsset = AVURLAsset(url: source)
        let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio)
        let sourceDuration = try await sourceAsset.load(.duration)
        let exporter = VideoExporter()
        let destination = directory.appendingPathComponent("decorated-export-\(UUID().uuidString).mov")
        try await exporter.export(source: source, destination: destination, backdrop: .aurora, showFrame: true,
                                  quarterTurns: 1, flipped: true)
        let result = AVURLAsset(url: destination)
        guard let track = try await result.loadTracks(withMediaType: .video).first else {
            throw VideoExportFailure.message(L("Test: traccia video assente."))
        }
        let size = try await track.load(.naturalSize)
        let descriptions = try await track.load(.formatDescriptions)
        let duration = try await result.load(.duration)
        let outputAudio = try await result.loadTracks(withMediaType: .audio)
        guard size.width > 0, size.height > 0, size.width <= 1920, size.height <= 1920,
              abs(duration.seconds - sourceDuration.seconds) < 0.1,
              outputAudio.count == sourceAudio.count,
              descriptions.first.map({ CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }) == true else {
            throw VideoExportFailure.message(L("Test: dimensioni, durata, audio o codec non corretti."))
        }
        let trimStart = min(0.1,sourceDuration.seconds / 4)
        let trimEnd = min(trimStart + 0.3,sourceDuration.seconds)
        for format in [CompositionFormat.portrait, .square, .landscape] {
            let presetDestination = directory.appendingPathComponent("\(format.id)-\(UUID().uuidString).mov")
            try await exporter.export(source:source,destination:presetDestination,backdrop:.paper,showFrame:true,
                                      quarterTurns:0,flipped:false,trimStart:trimStart,trimEnd:trimEnd,format:format)
            let presetAsset = AVURLAsset(url:presetDestination)
            guard let presetTrack = try await presetAsset.loadTracks(withMediaType:.video).first else {
                throw VideoExportFailure.message(L("Test: traccia del formato social assente."))
            }
            let presetSize = try await presetTrack.load(.naturalSize)
            let presetDuration = try await presetAsset.load(.duration)
            let presetAudio = try await presetAsset.loadTracks(withMediaType:.audio)
            guard presetSize == format.exportSize, abs(presetDuration.seconds - (trimEnd - trimStart)) < 0.1,
                  presetAudio.count == sourceAudio.count else {
                throw VideoExportFailure.message(L("Test: formato social, taglio o audio non corretti."))
            }
        }
        return "PASS: H.264, rotation, mirroring, frame and background; \(Int(size.width))×\(Int(size.height)), \(outputAudio.count) audio tracks; 9:16, 1:1, 16:9 formats with trim and audio; \(destination.lastPathComponent)"
    }
}
