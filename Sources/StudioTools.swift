// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import Vision

enum StudioTextRecognition {
    static func read(_ data: Data) async -> String {
        await Task.detached(priority:.userInitiated) {
            let request = PrivacyScanner.localTextRequest()
            request.automaticallyDetectsLanguage = true; request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(data:data).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
            } catch { return "" }
        }.value
    }
}

struct StudioImageContext: Identifiable {
    let id = UUID()
    let image: NSImage
}

struct StudioBugReportContext: Identifiable {
    let id = UUID()
    let original: NSImage
    let annotated: NSImage
    let masks: [PrivacyMask]
}

/// Reusable appearance only: source images, paths, masks and recognized text are never saved.
struct StudioStyle: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var backdrop: String
    var showFrame: Bool
    var rotation: Int
    var flipped: Bool
    var zoom: Double
    var format: String
    var exportScale: Double

    var isValid: Bool {
        !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count <= 60 &&
        Backdrop(rawValue:backdrop) != nil && CompositionFormat(rawValue:format) != nil &&
        (0...3).contains(rotation) && zoom.isFinite && (0.5...2).contains(zoom) &&
        exportScale.isFinite && [1.0,2.0,3.0].contains(exportScale)
    }
}

enum StudioStyleStore {
    private static let key = "studioStyles.v1"
    static func load(defaults: UserDefaults = .standard) -> [StudioStyle] {
        guard let data = defaults.data(forKey:key),
              let values = try? JSONDecoder().decode([StudioStyle].self,from:data) else { return [] }
        var seen = Set<UUID>()
        return Array(values.filter { $0.isValid && seen.insert($0.id).inserted }.prefix(20))
    }
    static func save(_ styles: [StudioStyle], defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(Array(styles.filter(\.isValid).prefix(20))),forKey:key)
    }
}

/// Keep drawings attached to the same content when the canvas proportions change.
enum CanvasAnnotations {
    static func reproject(_ marks: [Mark], from: CGSize, to: CGSize,
                          sourceAspect: CGFloat, quarterTurns: Int) -> [Mark] {
        guard from.width > 0, from.height > 0, to.width > 0, to.height > 0,
              sourceAspect.isFinite, sourceAspect > 0 else { return marks }
        let ratio = quarterTurns % 2 == 0 ? sourceAspect : 1 / sourceAspect
        let oldWidth = min(from.width * 0.86,from.height * 0.84 * ratio)
        let newWidth = min(to.width * 0.86,to.height * 0.84 * ratio)
        guard oldWidth > 0 else { return marks }
        let scale = newWidth / oldWidth
        return marks.map { mark in
            var result = mark
            result.points = mark.points.map { point in
                CGPoint(x:((point.x * from.width - from.width / 2) * scale + to.width / 2) / to.width,
                        y:((point.y * from.height - from.height / 2) * scale + to.height / 2) / to.height)
            }
            return result
        }
    }
}

@MainActor extension StudioModel {
    var hasImageContent: Bool { demo || image != nil || engine.isRunning }

    func sourceSnapshot() -> NSImage? {
        if let source = imported ?? frozen ?? engine.snapshot() { return source }
        guard demo else { return nil }
        let renderer = ImageRenderer(content:DemoScreen().frame(width:490,height:1000).preferredColorScheme(.dark))
        renderer.scale = 1
        return renderer.nsImage
    }

    func compositionSnapshot(source: NSImage, format: CompositionFormat? = nil) -> NSImage? {
        let chosen = format ?? compositionFormat
        let size = chosen.exportSize ?? CGSize(width:1000,height:1000 * canvasSize.height / max(1,canvasSize.width))
        let renderer = ImageRenderer(content:StudioCanvas(image:source,demo:false,backdrop:backdrop,frame:showFrame,
            rotation:rotation,flipped:flipped,zoom:zoom,grid:false,marks:marks,annotationMode:false,onPoint:nil,
            format:chosen,privacyMasks:privacyMasks).frame(width:size.width,height:size.height).preferredColorScheme(.dark))
        renderer.scale = 1
        return renderer.nsImage
    }

    func editPrivacy() {
        guard let source = sourceSnapshot() else { tell(L("Apri un’immagine o collega una sorgente")); return }
        invalidateOCR()
        frozen = source; imported = nil; demo = false; annotationMode = false
        privacyContext = StudioImageContext(image:source)
    }

    func prepareBugReport() {
        guard let original = sourceSnapshot(), let annotated = compositionSnapshot(source:original) else {
            tell(L("Serve un fotogramma per creare una segnalazione")); return
        }
        bugReportContext = StudioBugReportContext(original:original,annotated:annotated,masks:privacyMasks)
    }

    func saveStyle() {
        let name = String(styleName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { tell(L("Dai un nome allo stile")); return }
        var style = StudioStyle(name:name,backdrop:backdrop.rawValue,showFrame:showFrame,rotation:rotation,
            flipped:flipped,zoom:zoom,format:compositionFormat.rawValue,exportScale:exportScale)
        if let existing = savedStyles.first(where:{ $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            style.id = existing.id
        }
        var updated = savedStyles.filter { $0.id != style.id }
        updated.insert(style,at:0)
        do {
            try StudioStyleStore.save(updated)
            savedStyles = Array(updated.prefix(20)); selectedStyleID = style.id
            tell(L("Stile salvato sul Mac"))
        } catch { tell(LF("Stile: %@", error.localizedDescription)) }
    }

    func applySelectedStyle() {
        guard let style = savedStyles.first(where:{ $0.id == selectedStyleID }), style.isValid,
              let savedBackdrop = Backdrop(rawValue:style.backdrop),
              let savedFormat = CompositionFormat(rawValue:style.format) else { return }
        backdrop = savedBackdrop; showFrame = style.showFrame; rotation = style.rotation
        flipped = style.flipped; zoom = style.zoom; compositionFormat = savedFormat
        exportScale = style.exportScale; styleName = style.name
    }

    func deleteSelectedStyle() {
        guard let id = selectedStyleID else { return }
        let updated = savedStyles.filter { $0.id != id }
        do {
            try StudioStyleStore.save(updated); savedStyles = updated; selectedStyleID = nil
        } catch { tell(error.localizedDescription) }
    }

    private func creatorDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L("Dove salvare il pacchetto creator?")
        panel.message = L("Verrà creata una nuova cartella con tre formati, copertina e riepilogo.")
        panel.prompt = L("Crea pacchetto"); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func exportCreatorImages() {
        guard !creatorExporter.isExporting, !exporter.isExporting, let source = sourceSnapshot(),
              let directory = creatorDirectory() else { return }
        let bg = backdrop, frame = showFrame, turns = rotation, flip = flipped, currentZoom = zoom
        let currentMarks = marks, masks = privacyMasks, title = creatorTitle
        let annotationSize = compositionFormat.fittedSize(in:canvasSize)
        Task {
            do {
                let url = try await creatorExporter.exportImages(image:source,directory:directory,backdrop:bg,
                    showFrame:frame,quarterTurns:turns,flipped:flip,zoom:currentZoom,marks:currentMarks,
                    privacyMasks:masks,coverTitle:title,annotationCanvasSize:annotationSize)
                addRecent(url); tell(L("Pacchetto immagini creato"))
            } catch is CancellationError { tell(L("Pacchetto annullato")) }
            catch { tell(LF("Pacchetto: %@", error.localizedDescription)) }
        }
    }

    func exportCreatorVideo() {
        guard !creatorExporter.isExporting, !exporter.isExporting, let source = videoSource,
              let directory = creatorDirectory() else { return }
        let bg = backdrop, frame = showFrame, turns = rotation, flip = flipped, start = trimStart, end = trimEnd
        let masks = videoPrivacyMasks, title = creatorTitle
        Task {
            do {
                let url = try await creatorExporter.exportVideo(source:source,directory:directory,backdrop:bg,
                    showFrame:frame,quarterTurns:turns,flipped:flip,trimStart:start,trimEnd:end == 0 ? nil : end,
                    privacyMasks:masks,coverTitle:title)
                addRecent(url); showVideoExport = false; tell(L("Pacchetto video creato"))
            } catch is CancellationError { tell(L("Pacchetto annullato")) }
            catch { tell(LF("Pacchetto: %@", error.localizedDescription)) }
        }
    }
}

struct StudioToolsPanel: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: StudioModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("PRIVACY & SEGNALAZIONI")).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary)
            Button { model.editPrivacy() } label: { Label(L("Oscura dati"),systemImage:"rectangle.dashed") }
                .disabled(!model.hasImageContent)
            if !model.privacyMasks.isEmpty {
                Text(model.privacyMasks.count == 1 ? L("1 area oscurata negli screenshot e nel testo OCR") : LF("%d aree oscurate negli screenshot e nel testo OCR", model.privacyMasks.count)).font(.system(size:10)).foregroundStyle(.secondary)
                Button(L("Rimuovi maschere")) { model.privacyMasks = [] }
            }
            Button { model.prepareBugReport() } label: { Label(L("Crea segnalazione bug"),systemImage:"ladybug") }
                .disabled(!model.hasImageContent)
            Text(L("Il report include descrizione, immagini e testo. L’originale non oscurato è escluso salvo tua scelta."))
                .font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            Text(L("PACCHETTO CREATOR")).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary)
            TextField(L("Titolo copertina (facoltativo)"),text:$model.creatorTitle)
            Button { model.exportCreatorImages() } label: { Label(L("Esporta 3 formati + copertina"),systemImage:"square.stack.3d.up") }
                .disabled(!model.hasImageContent || model.creatorExporter.isExporting || model.exporter.isExporting)
            Text(L("Per i video usa Pacchetto creator nel pannello Incornicia video.")).font(.system(size:10)).foregroundStyle(.secondary)
            if model.creatorExporter.isExporting {
                ProgressView(value:model.creatorExporter.progress)
                Button(L("Annulla pacchetto")) { model.creatorExporter.cancel() }
            }
            Divider()
            Text(L("IL TUO STILE")).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(.secondary)
            TextField(L("Nome stile"),text:$model.styleName)
            Button(L("Salva stile attuale")) { model.saveStyle() }
            if !model.savedStyles.isEmpty {
                Picker(L("Stile"),selection:$model.selectedStyleID) {
                    Text(L("Scegli…")).tag(UUID?.none)
                    ForEach(model.savedStyles) { Text($0.name).tag(Optional($0.id)) }
                }.onChange(of:model.selectedStyleID) { _, _ in model.applySelectedStyle() }
                Button(L("Elimina stile selezionato")) { model.deleteSelectedStyle() }.disabled(model.selectedStyleID == nil)
            }
            Text(L("Lo stile salva solo l’aspetto, senza immagini, dati OCR o maschere.")).font(.system(size:10)).foregroundStyle(.secondary)
        }
    }
}
