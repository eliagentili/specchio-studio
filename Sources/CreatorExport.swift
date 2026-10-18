import AppKit
@preconcurrency import AVFoundation
import Combine
import SwiftUI

private enum CreatorExportFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// A complete set of social formats, published only when every file is ready.
@MainActor
final class CreatorExport: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var errorMessage: String?
    private let videoExporter = VideoExporter()
    private var cancelled = false
    private var progressObservation: AnyCancellable?

    private static let formats: [(CompositionFormat, String)] = [
        (.portrait, "portrait-9x16"), (.square, "square-1x1"), (.landscape, "landscape-16x9")
    ]

    func cancel() { cancelled = true; videoExporter.cancel() }

    func exportVideo(source: URL, directory: URL, backdrop: Backdrop, showFrame: Bool,
                     quarterTurns: Int, flipped: Bool, trimStart: Double? = nil, trimEnd: Double? = nil,
                     privacyMasks: [PrivacyMask] = [], coverTitle: String = "") async throws -> URL {
        try begin()
        var stage: URL?
        defer { finish(stage: stage) }
        do {
            let workspace = try makeWorkspace(in: directory)
            stage = workspace.stage
            var files: [Manifest.Output] = []
            for (index, entry) in Self.formats.enumerated() {
                try checkCancellation()
                let output = workspace.stage.appendingPathComponent(entry.1 + ".mov")
                progressObservation = videoExporter.$progress.dropFirst().sink { [weak self] fraction in
                    self?.progress = (Double(index) + fraction) / 3 * 0.9
                }
                try await videoExporter.export(source: source, destination: output, backdrop: backdrop, showFrame: showFrame,
                                               quarterTurns: quarterTurns, flipped: flipped, trimStart: trimStart,
                                               trimEnd: trimEnd, format: entry.0, privacyMasks: privacyMasks)
                progressObservation = nil
                let asset = AVURLAsset(url: output)
                let seconds = try await asset.load(.duration).seconds
                let audioCount = try await asset.loadTracks(withMediaType: .audio).count
                let size = entry.0.exportSize!
                files.append(.init(file: output.lastPathComponent, width: Int(size.width), height: Int(size.height),
                                   durationSeconds: seconds, audioTracks: audioCount))
            }
            try checkCancellation()
            // Decode the finished landscape rendition: the cover contains exactly
            // its burned redactions, orientation and composition.
            let asset = AVURLAsset(url: workspace.stage.appendingPathComponent("landscape-16x9.mov"))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try await generator.image(at: .zero).image
            let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            try writePNG(cover(image: image, title: coverTitle), to: workspace.stage.appendingPathComponent("cover.png"))
            files.append(.init(file: "cover.png", width: 1920, height: 1080, durationSeconds: nil, audioTracks: nil))
            progress = 0.96
            try writeManifest(kind: "video", outputs: files, maskCount: privacyMasks.count, coverTitle: coverTitle, to: workspace.stage)
            try checkCancellation()
            try FileManager.default.moveItem(at: workspace.stage, to: workspace.destination)
            stage = nil
            progress = 1
            return workspace.destination
        } catch { errorMessage = error is CancellationError ? "Pacchetto annullato." : error.localizedDescription; throw error }
    }

    func exportImages(image: NSImage, directory: URL, backdrop: Backdrop, showFrame: Bool,
                      quarterTurns: Int, flipped: Bool, zoom: Double, marks: [Mark],
                      privacyMasks: [PrivacyMask] = [], coverTitle: String = "", annotationCanvasSize: CGSize? = nil) async throws -> URL {
        try begin()
        var stage: URL?
        defer { finish(stage: stage) }
        do {
            let workspace = try makeWorkspace(in: directory)
            stage = workspace.stage
            guard let safeImage = PrivacyRenderer.redactedImage(image, masks: privacyMasks) else {
                throw CreatorExportFailure.message("Impossibile preparare l’immagine con le maschere privacy.")
            }
            var files: [Manifest.Output] = []
            var landscape: NSImage?
            for (index, entry) in Self.formats.enumerated() {
                try checkCancellation()
                let size = entry.0.exportSize!
                let projectedMarks = annotationCanvasSize.map {
                    CanvasAnnotations.reproject(marks, from: $0, to: size, sourceAspect: aspect(image), quarterTurns: quarterTurns)
                } ?? marks
                let renderer = ImageRenderer(content: StudioCanvas(image: safeImage, demo: false, backdrop: backdrop,
                    frame: showFrame, rotation: quarterTurns, flipped: flipped, zoom: zoom, grid: false,
                    marks: projectedMarks, annotationMode: false, onPoint: nil, format: entry.0)
                    .frame(width: size.width, height: size.height).preferredColorScheme(.dark))
                renderer.scale = 1
                guard let rendered = renderer.nsImage else { throw CreatorExportFailure.message("Impossibile renderizzare il formato \(entry.0.rawValue).") }
                try writePNG(rendered, to: workspace.stage.appendingPathComponent(entry.1 + ".png"))
                if entry.0 == .landscape { landscape = rendered }
                files.append(.init(file: entry.1 + ".png", width: Int(size.width), height: Int(size.height), durationSeconds: nil, audioTracks: nil))
                progress = Double(index + 1) / 3 * 0.9
                await Task.yield()
            }
            try checkCancellation()
            guard let landscape else { throw CreatorExportFailure.message("Copertina non disponibile.") }
            try writePNG(cover(image: landscape, title: coverTitle), to: workspace.stage.appendingPathComponent("cover.png"))
            files.append(.init(file: "cover.png", width: 1920, height: 1080, durationSeconds: nil, audioTracks: nil))
            try writeManifest(kind: "image", outputs: files, maskCount: privacyMasks.count, coverTitle: coverTitle, to: workspace.stage)
            try checkCancellation()
            try FileManager.default.moveItem(at: workspace.stage, to: workspace.destination)
            stage = nil
            progress = 1
            return workspace.destination
        } catch { errorMessage = error is CancellationError ? "Pacchetto annullato." : error.localizedDescription; throw error }
    }

    private func begin() throws {
        guard !isExporting else { throw CreatorExportFailure.message("Un pacchetto creator è già in preparazione.") }
        isExporting = true; cancelled = false; progress = 0; errorMessage = nil
    }
    private func finish(stage: URL?) {
        progressObservation = nil
        if let stage { try? FileManager.default.removeItem(at: stage) }
        isExporting = false
    }
    private func checkCancellation() throws { if cancelled || Task.isCancelled { throw CancellationError() } }
    private func makeWorkspace(in directory: URL) throws -> (stage: URL, destination: URL) {
        try checkCancellation()
        var isDirectory: ObjCBool = false
        guard directory.isFileURL, FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CreatorExportFailure.message("Scegli una cartella locale esistente per il pacchetto.")
        }
        let identifier = UUID().uuidString.lowercased()
        let stage = directory.appendingPathComponent(".specchio-creator-" + identifier, isDirectory: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destination = directory.appendingPathComponent("Specchio-Creator-" + formatter.string(from: Date()) + "-" + identifier.prefix(8), isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        return (stage, destination)
    }
    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CreatorExportFailure.message("Impossibile scrivere l’immagine PNG.")
        }
        try data.write(to: url, options: .atomic)
    }
    private func cover(image: NSImage, title: String) throws -> NSImage {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let renderer = ImageRenderer(content: ZStack(alignment: .bottomLeading) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            if !trimmed.isEmpty {
                Text(trimmed).font(.system(size: 58, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(3).padding(28).background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
                    .padding(50)
            }
        }.frame(width: 1920, height: 1080).preferredColorScheme(.dark))
        renderer.scale = 1
        guard let result = renderer.nsImage else { throw CreatorExportFailure.message("Impossibile creare la copertina.") }
        return result
    }
    private struct Manifest: Codable {
        struct Output: Codable { var file: String; var width: Int; var height: Int; var durationSeconds: Double?; var audioTracks: Int? }
        var schemaVersion = 1
        var application = "Specchio Studio"
        var createdAt: String
        var kind: String
        var coverTitle: String
        var privacyMaskCount: Int
        var privacyNotice = "Opaque privacy masks are burned into every rendition and cover. Video masks are fixed areas for the complete selected clip; inspect all frames before sharing."
        var outputs: [Output]
    }
    private func writeManifest(kind: String, outputs: [Manifest.Output], maskCount: Int, coverTitle: String, to directory: URL) throws {
        let manifest = Manifest(createdAt: ISO8601DateFormatter().string(from: Date()), kind: kind,
                                coverTitle: String(coverTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
                                privacyMaskCount: maskCount, outputs: outputs)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }
}
