import SwiftUI
import AppKit
import Vision
import AVKit
import UniformTypeIdentifiers
import Combine

enum Backdrop: String, CaseIterable, Identifiable {
    case midnight = "Grafite", aurora = "Aurora", ocean = "Oceano", paper = "Carta", transparent = "Trasparente"
    var id: String { rawValue }
    var colors: [Color] {
        switch self {
        case .midnight: return [Color(red:0.12,green:0.14,blue:0.18),Color(red:0.05,green:0.06,blue:0.08)]
        case .aurora: return [Color(red:0.17,green:0.43,blue:0.38),Color(red:0.14,green:0.16,blue:0.31)]
        case .ocean: return [Color(red:0.15,green:0.35,blue:0.61),Color(red:0.08,green:0.14,blue:0.29)]
        case .paper: return [.white,Color(white:0.88)]
        case .transparent: return [.clear,.clear]
        }
    }
}

struct Mark: Identifiable { var id = UUID(); var points: [CGPoint]; var color: Color }
struct RecentCapture: Identifiable { var id: String { url.path }; var url: URL; var date: Date }

@MainActor final class StudioModel: ObservableObject {
    let engine = CaptureEngine()
    let screen = ScreenSource()
    let wireless = WirelessSource()
    let exporter = VideoExporter()
    let creatorExporter = CreatorExport()
    @Published var tab = "Studio"
    @Published var selectedDevice = ""
    @Published var backdrop = Backdrop.aurora
    @Published var showFrame = true
    @Published var compositionFormat = CompositionFormat.adaptive
    @Published var rotation = 0
    @Published var flipped = false
    @Published var pin = false
    @Published var grid = false
    @Published var zoom = 1.0
    @Published var annotationMode = false
    @Published var marks: [Mark] = []
    @Published var privacyMasks: [PrivacyMask] = [] { didSet { invalidateOCR() } }
    @Published var videoPrivacyMasks: [PrivacyMask] = []
    @Published var privacyContext: StudioImageContext?
    @Published var bugReportContext: StudioBugReportContext?
    @Published var bugReportBusy = false
    @Published var savedStyles: [StudioStyle] = []
    @Published var styleName = "Il mio stile"
    @Published var selectedStyleID: UUID?
    @Published var creatorTitle = ""
    @Published var frozen: NSImage?
    @Published var imported: NSImage?
    @Published var demo = false
    @Published var notification = ""
    @Published var recent: [RecentCapture] = []
    @Published var codec: RecordingCodec = .h264
    @Published var quality: RecordingQuality = .high
    @Published var showInspector = true
    @Published var recordingStart: Date?
    @Published var recordBusy = false
    @Published var countdown = 0
    @Published var countdownSetting = 3
    @Published var ocrBusy = false
    @Published var exportScale = 2.0
    @Published var includesScreenAudio = true
    @Published var canvasSize = CGSize(width:800,height:500)
    @Published var videoSource: URL?
    @Published var showVideoExport = false
    @Published var trimStart = 0.0
    @Published var trimEnd = 0.0
    private var observers = Set<AnyCancellable>()
    private var recordingTask: Task<Void,Never>?
    private var messageTask: Task<Void,Never>?
    private var ocrGeneration = 0

    init() {
        savedStyles = StudioStyleStore.load()
        let saved = UserDefaults.standard.stringArray(forKey:"recentCaptures") ?? []
        recent = saved.compactMap { path in
            guard FileManager.default.fileExists(atPath:path) else { return nil }
            return RecentCapture(url:URL(fileURLWithPath:path),date:(try? FileManager.default.attributesOfItem(atPath:path)[.modificationDate] as? Date) ?? Date())
        }
        StudioRegistry.shared.models.append(.init(value:self))
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&observers)
        wireless.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&observers)
        screen.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&observers)
        exporter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&observers)
        creatorExporter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in:&observers)
        engine.$isRecording.dropFirst().removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            if value { self.recordingStart = Date() }
            else if self.recordingStart != nil {
                self.recordingStart = nil
                if let url = self.engine.recordingURL, FileManager.default.fileExists(atPath:url.path) { self.addRecent(url) }
            }
        }.store(in:&observers)
        engine.$recordingURL.compactMap { $0 }.sink { [weak self] url in
            if FileManager.default.fileExists(atPath:url.path) { self?.addRecent(url) }
        }.store(in:&observers)
        if CommandLine.arguments.contains("--demo") { demo = true }
    }
    var image: NSImage? { imported ?? frozen ?? engine.previewImage }
    func tell(_ text: String) {
        notification = text; messageTask?.cancel()
        messageTask = Task { try? await Task.sleep(for:.seconds(5)); if !Task.isCancelled { notification = "" } }
    }
    func addRecent(_ url: URL) {
        recent.removeAll { $0.url == url }; recent.insert(.init(url:url,date:Date()),at:0)
        recent = Array(recent.prefix(60)); UserDefaults.standard.set(recent.map(\.url.path),forKey:"recentCaptures")
    }
    func connect() {
        guard !selectedDevice.isEmpty else { return }
        guard canSwitchSource() else { return }
        invalidateOCR()
        cancelCountdown()
        Task {
            await wireless.stop(); await screen.stop(); imported = nil; frozen = nil; demo = false; marks = []; privacyMasks = []
            await engine.start(deviceID:selectedDevice)
        }
    }
    func startWireless() {
        guard canSwitchSource() else { return }
        invalidateOCR()
        cancelCountdown()
        Task {
            await screen.stop(); engine.stop()
            imported=nil; frozen=nil; demo=false; marks=[]; privacyMasks=[]
            await wireless.start(engine:engine)
        }
    }
    func pickScreen() {
        guard canSwitchSource() else { return }
        invalidateOCR()
        cancelCountdown()
        Task {
            await wireless.stop()
            imported = nil; frozen = nil; demo = false; marks = []; privacyMasks = []
            screen.start(engine:engine,includesAudio:includesScreenAudio)
        }
    }
    private func canSwitchSource() -> Bool {
        guard !engine.isRecording, !engine.isFinalizing else {
            tell("Termina la registrazione prima di cambiare sorgente")
            return false
        }
        return true
    }
    func disconnect() {
        invalidateOCR()
        cancelCountdown()
        Task { await finishRecording(); await wireless.stop(); await screen.stop(); engine.stop() }
    }
    func shutdown() async {
        cancelCountdown(); exporter.cancel(); creatorExporter.cancel()
        while exporter.isExporting || creatorExporter.isExporting || bugReportBusy { try? await Task.sleep(for:.milliseconds(40)) }
        await finishRecording(); await wireless.stop(); await screen.stop(); engine.stop()
    }
    func cancelCountdown() { recordingTask?.cancel(); recordingTask = nil; countdown = 0 }
    func record() {
        if countdown > 0 { cancelCountdown(); return }
        if engine.isRecording { Task { await finishRecording() }; return }
        guard engine.isRunning, !engine.isFinalizing, !recordBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = filename("mov"); panel.title = "Salva registrazione originale"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recordingTask = Task {
            for remaining in stride(from:countdownSetting,through:1,by:-1) {
                countdown = remaining; try? await Task.sleep(for:.seconds(1))
                if Task.isCancelled { countdown = 0; return }
            }
            countdown = 0
            guard !Task.isCancelled, engine.isRunning else { return }
            engine.startRecording(to:url,codec:codec,quality:quality)
        }
    }
    func finishRecording() async {
        guard (engine.isRecording || engine.isFinalizing), !recordBusy else { return }
        recordBusy = true; await engine.stopRecording(); recordBusy = false; recordingStart = nil
        if let url = engine.recordingURL, FileManager.default.fileExists(atPath:url.path), engine.errorMessage == nil {
            addRecent(url); tell("Registrazione salvata")
        }
    }
    func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf:url) else { return }
        imported = img; frozen = nil; demo = false; marks = []; privacyMasks = []; tell("Immagine aperta nello studio")
    }
    func selectVideo(_ url: URL? = nil) {
        guard !exporter.isExporting, !creatorExporter.isExporting else { return }
        if let url { videoSource = url }
        else {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let source = panel.url else { return }
            videoSource = source
        }
        trimStart = 0; trimEnd = 0; videoPrivacyMasks = []; showVideoExport = true
    }
    func exportVideo() {
        guard let source = videoSource, !exporter.isExporting, !creatorExporter.isExporting else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.quickTimeMovie]; panel.nameFieldStringValue = filename("mov")
        panel.title = "Esporta video con composizione"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let bg = backdrop, frame = showFrame, turns = rotation, flip = flipped, start = trimStart, end = trimEnd, format = compositionFormat, masks = videoPrivacyMasks
        Task {
            do {
                try await exporter.export(source:source,destination:destination,backdrop:bg,showFrame:frame,quarterTurns:turns,flipped:flip,trimStart:start,trimEnd:end == 0 ? nil : end,format:format,privacyMasks:masks)
                addRecent(destination); showVideoExport = false; tell("Video con composizione esportato")
            } catch { tell("Esportazione: \(error.localizedDescription)") }
        }
    }
    func freeze() {
        invalidateOCR()
        if frozen != nil { frozen = nil; marks = []; privacyMasks = []; return }
        frozen = engine.snapshot(); if frozen == nil { tell("Collega una sorgente per bloccare un fotogramma") }
    }
    func prepareAnnotation() {
        if !annotationMode, imported == nil, frozen == nil, !demo { frozen = engine.snapshot() }
        annotationMode.toggle()
    }
    func filename(_ ext: String) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return "Specchio_\(formatter.string(from:Date())).\(ext)"
    }
    func exportImage(copy: Bool = false, original: Bool = false) {
        guard demo || image != nil || engine.snapshot() != nil else { tell("Nessun fotogramma disponibile"); return }
        let img: NSImage?
        if original {
            img = sourceSnapshot().flatMap { PrivacyRenderer.redactedImage($0,masks:privacyMasks) }
        }
        else {
            let source = imported ?? frozen ?? engine.snapshot()
            let size = compositionFormat.exportSize ?? CGSize(width:1000,height:1000 * canvasSize.height/max(1,canvasSize.width))
            let renderer = ImageRenderer(content:StudioCanvas(image:source,demo:demo,backdrop:backdrop,frame:showFrame,rotation:rotation,flipped:flipped,zoom:zoom,grid:false,marks:marks,annotationMode:false,onPoint:nil,format:compositionFormat,privacyMasks:privacyMasks).frame(width:size.width,height:size.height).preferredColorScheme(.dark))
            renderer.scale = exportScale; img = renderer.nsImage
        }
        guard let img, let tiff = img.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff) else { tell("Impossibile creare l’immagine"); return }
        if copy {
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img]); tell("Immagine copiata"); return
        }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png,.jpeg]; panel.nameFieldStringValue = filename("png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let type: NSBitmapImageRep.FileType = ["jpg","jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        guard let data = bitmap.representation(using:type,properties:[.compressionFactor:0.95]) else { tell("Formato non disponibile"); return }
        do { try data.write(to:url,options:.atomic); addRecent(url); tell("Screenshot salvato") } catch { tell(error.localizedDescription) }
    }
    @discardableResult
    func recognizeText(pasteboard: NSPasteboard = .general,
                       recognition: @escaping @Sendable (Data) async -> String = { data in await StudioTextRecognition.read(data) }) -> Task<Void,Never>? {
        guard let raw = sourceSnapshot(), let img = PrivacyRenderer.redactedImage(raw,masks:privacyMasks), let data = img.tiffRepresentation else { tell("Serve un’immagine o un fotogramma per leggere il testo"); return nil }
        ocrGeneration &+= 1
        let generation = ocrGeneration
        ocrBusy = true
        return Task {
            let result = await recognition(data)
            guard generation == ocrGeneration else { return }
            ocrBusy = false
            if result.isEmpty { tell("Nessun testo riconosciuto") }
            else { pasteboard.clearContents(); pasteboard.setString(result,forType:.string); tell("Testo riconosciuto e copiato negli appunti") }
        }
    }
    func invalidateOCR() { ocrGeneration &+= 1; ocrBusy = false }
}

func aspect(_ image: NSImage?) -> CGFloat {
    guard let size = image?.size, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return 0.5 }
    return size.width / size.height
}

struct StudioView: View {
    @StateObject private var model = StudioModel()
    @StoredState private var window: NSWindow? = nil
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:220)
            Divider()
            VStack(spacing:0) {
                header
                Divider()
                if model.tab == "Studio" { workspace }
                else if model.tab == "Libreria" { library }
                else { guide }
                footer
            }
        }
        .background(Color(red:0.055,green:0.065,blue:0.078))
        .tint(Color.mint)
        .background(WindowReader { w in window = w; w.level = model.pin ? .floating : .normal })
        .onChange(of:model.pin) { _, value in window?.level = value ? .floating : .normal }
        .onReceive(NotificationCenter.default.publisher(for:.showStudioGuide)) { _ in model.tab = "Guida" }
        .onDisappear { Task { await model.shutdown() } }
        .sheet(isPresented:$model.showVideoExport) { VideoExportSheet(model:model) }
        .sheet(item:$model.privacyContext) { context in
            PrivacyEditorView(image:context.image,masks:model.privacyMasks,onApply:{ masks in
                model.privacyMasks = masks; model.privacyContext = nil
            },onCancel:{ model.privacyContext = nil })
        }
        .sheet(item:$model.bugReportContext) { context in
            BugReportSheet(original:context.original,annotated:context.annotated,privacyMasks:context.masks,onComplete:{ url in
                model.addRecent(url); model.bugReportContext = nil; model.tell("Segnalazione salvata")
            },onCancel:{ model.bugReportContext = nil },onBusyChange:{ model.bugReportBusy = $0 })
        }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:26) {
            HStack(spacing:11) {
                Image(systemName:"rectangle.portrait.on.rectangle.portrait.angled").font(.system(size:26)).foregroundStyle(.mint)
                VStack(alignment:.leading,spacing:2) { Text("SPECCHIO").font(.system(size:16,weight:.bold,design:.rounded)); Text("STUDIO  /  01").font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.secondary) }
            }.padding(.top,14)
            VStack(spacing:7) {
                nav("Studio",icon:"slider.horizontal.3")
                nav("Libreria",icon:"square.stack.3d.up")
                nav("Guida",icon:"book.closed")
            }
            SourceControls(model:model)
            Spacer()
            VStack(alignment:.leading,spacing:9) {
                Label("Tutto resta sul tuo Mac",systemImage:"lock.shield").font(.system(size:11,weight:.medium))
                Text("Acquisizioni locali. Nessun account.\nNessun watermark.").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(13).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
        }.padding(18)
    }
    private func nav(_ name: String, icon: String) -> some View {
        Button { model.tab = name } label: {
            HStack { Image(systemName:icon).frame(width:22); Text(name); Spacer(); if model.tab == name { Circle().fill(.mint).frame(width:5,height:5) } }
                .font(.system(size:13,weight:.medium)).padding(11).background(model.tab == name ? .white.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain)
    }
    private var header: some View {
        HStack {
            VStack(alignment:.leading,spacing:5) {
                Text(model.tab == "Studio" ? "Il tuo dispositivo. In primo piano." : model.tab).font(.system(size:20,weight:.semibold))
                Text(model.tab == "Studio" ? "MIRROR  /  CAPTURE  /  CREATE" : "SPECCHIO STUDIO").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.importImage() } label: { Label("Apri immagine",systemImage:"square.and.arrow.down") }
            Button { model.selectVideo() } label: { Label("Incornicia video",systemImage:"film") }.disabled(model.exporter.isExporting || model.creatorExporter.isExporting)
            Button { model.prepareBugReport() } label: { Image(systemName:"ladybug") }.help("Crea segnalazione bug").disabled(!model.hasImageContent)
            Button { model.pin.toggle() } label: { Image(systemName:model.pin ? "pin.fill" : "pin") }.help("Sempre in primo piano")
            Button { window?.toggleFullScreen(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.help("Schermo intero")
        }.buttonStyle(.bordered).controlSize(.small).padding(22)
    }
    private var workspace: some View {
        HStack(spacing:0) {
            VStack(spacing:0) {
                CaptureToolbar(model:model)
                ZStack {
                    StudioCanvas(image:model.image,demo:model.demo,backdrop:model.backdrop,frame:model.showFrame,rotation:model.rotation,flipped:model.flipped,zoom:model.zoom,grid:model.grid,marks:model.marks,annotationMode:model.annotationMode,onPoint:{ point, isNew in
                        if isNew || model.marks.isEmpty { model.marks.append(Mark(points:[point],color:.orange)) }
                        else { model.marks[model.marks.count-1].points.append(point) }
                    },format:model.compositionFormat,privacyMasks:model.privacyMasks)
                    .onGeometryChange(for:CGSize.self) { $0.size } action: { model.canvasSize = $0 }
                    if model.image == nil && !model.demo { emptyState }
                    if model.countdown > 0 { Text("\(model.countdown)").font(.system(size:120,weight:.bold,design:.rounded)).shadow(radius:20) }
                    if model.frozen != nil { VStack { HStack { Label("FERMO IMMAGINE",systemImage:"pause.fill").font(.system(size:10,weight:.bold)).padding(9).background(.ultraThinMaterial,in:Capsule()); Spacer() }; Spacer() }.padding(22) }
                }.clipped()
                HStack {
                    Text("ANTEPRIMA").font(.system(size:9,design:.monospaced)).tracking(1.7).foregroundStyle(.secondary)
                    Spacer(); Image(systemName:"minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value:$model.zoom,in:0.5...2).frame(width:100)
                    Text("\(Int(model.zoom*100))%").font(.system(size:10,design:.monospaced)).frame(width:36)
                    Button("Adatta") { model.zoom = 1 }
                }.controlSize(.mini).padding(14)
            }
            Divider()
            inspector.frame(width:220)
        }
    }
    private var emptyState: some View {
        VStack(spacing:20) {
            Image(systemName:"cable.connector").font(.system(size:48,weight:.ultraLight)).foregroundStyle(.mint)
            VStack(spacing:10) { Text("Fai spazio al tuo schermo.").font(.system(size:24,weight:.medium)); Text(model.wireless.isListening ? "Su iPhone o iPad: Centro di Controllo → Duplica schermo\nScegli Specchio Studio e inserisci il codice, se richiesto." : "Collega un iPhone o iPad via USB\noppure premi Wireless per collegarlo senza cavo.").font(.system(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4) }
            HStack { Button("Scegli finestra o schermo") { model.pickScreen() }.buttonStyle(.borderedProminent); Button("Esplora la demo") { model.demo = true }.buttonStyle(.bordered) }
            Text("La demo è un’illustrazione, senza connessione a dispositivi.").font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(30).background(.black.opacity(0.38),in:RoundedRectangle(cornerRadius:24)).padding(25)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:23) {
                sectionLabel("COMPOSIZIONE")
                Picker("Formato",selection:$model.compositionFormat) { ForEach(CompositionFormat.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of:model.compositionFormat) { old, new in
                        model.marks = CanvasAnnotations.reproject(model.marks,from:old.fittedSize(in:model.canvasSize),
                            to:new.fittedSize(in:model.canvasSize),sourceAspect:model.image.map { aspect($0) } ?? 0.49,
                            quarterTurns:model.rotation)
                    }
                Text("Il formato vale per screenshot e video. Gli spazi liberi usano lo sfondo scelto.").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3)
                Picker("Sfondo",selection:$model.backdrop) { ForEach(Backdrop.allCases) { b in Text(b.rawValue).tag(b) } }.labelsHidden()
                HStack(spacing:8) { ForEach(Backdrop.allCases) { b in Button { model.backdrop = b } label: { RoundedRectangle(cornerRadius:8).fill(LinearGradient(colors:b.colors,startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:28,height:28).overlay(RoundedRectangle(cornerRadius:8).stroke(model.backdrop == b ? .mint : .white.opacity(0.2),lineWidth:2)) }.buttonStyle(.plain).help(b.rawValue) } }
                Toggle("Cornice dispositivo",isOn:$model.showFrame)
                Toggle("Griglia composizione",isOn:$model.grid)
                Toggle("Specchia orizzontalmente",isOn:$model.flipped)
                HStack { Text("Ruota"); Spacer(); Button { model.rotation = (model.rotation+3)%4 } label: { Image(systemName:"rotate.left") }; Button { model.rotation = (model.rotation+1)%4 } label: { Image(systemName:"rotate.right") } }
                Divider(); sectionLabel("REGISTRAZIONE ORIGINALE")
                Picker("Codec",selection:$model.codec) { Text("H.264").tag(RecordingCodec.h264); Text("HEVC").tag(RecordingCodec.hevc) }
                Picker("Qualità",selection:$model.quality) { Text("Standard").tag(RecordingQuality.standard); Text("Alta").tag(RecordingQuality.high); Text("Massima").tag(RecordingQuality.maximum) }
                Picker("Countdown",selection:$model.countdownSetting) { Text("Nessuno").tag(0); Text("3 secondi").tag(3); Text("5 secondi").tag(5) }
                Toggle("Audio finestra / schermo",isOn:$model.includesScreenAudio).disabled(model.engine.isRunning)
                Text("Registra il video originale. Per aggiungere sfondo e cornice usa Incornicia video dopo il salvataggio.").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3)
                Divider(); sectionLabel("SCREENSHOT & TESTO")
                Picker("Scala export",selection:$model.exportScale) { Text("1×").tag(1.0); Text("2×").tag(2.0); Text("3×").tag(3.0) }
                Button { model.exportImage() } label: { Label("Esporta composizione",systemImage:"camera") }.keyboardShortcut("s",modifiers:[.command,.shift])
                Button { model.exportImage(original:true) } label: { Label(model.privacyMasks.isEmpty ? "Salva fotogramma originale" : "Salva fotogramma oscurato",systemImage:"photo") }
                Button { model.exportImage(copy:true) } label: { Label("Copia composizione",systemImage:"doc.on.doc") }.keyboardShortcut("c",modifiers:[.command,.shift])
                Button { model.prepareAnnotation() } label: { Label(model.annotationMode ? "Termina annotazione" : "Disegna sul fotogramma",systemImage:"pencil.tip.crop.circle") }
                if !model.marks.isEmpty { HStack { Button("Annulla tratto") { _ = model.marks.popLast() }; Button("Pulisci") { model.marks = [] } }.controlSize(.mini) }
                Button { model.recognizeText() } label: { Label(model.ocrBusy ? "Lettura…" : "Copia testo con OCR",systemImage:"text.viewfinder") }.disabled(model.ocrBusy)
                Divider()
                StudioToolsPanel(model:model)
                Spacer()
            }.font(.system(size:11)).controlSize(.small).buttonStyle(.bordered).padding(18)
        }
    }
    private func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.2).foregroundStyle(.secondary) }
    private var footer: some View {
        StatusFooter(model:model)
    }
    private var library: some View {
        ScrollView {
            if model.recent.isEmpty { ContentUnavailableView("La tua prossima creazione inizia qui",systemImage:"photo.stack",description:Text("Screenshot e registrazioni salvati da Specchio appariranno in questa libreria." )).padding(.top,100) }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:220))],spacing:18) {
                ForEach(model.recent) { item in
                    VStack(alignment:.leading,spacing:10) {
                        Group { if let image = NSImage(contentsOf:item.url) { Image(nsImage:image).resizable().scaledToFit() } else { Image(systemName:item.url.hasDirectoryPath ? "folder" : "play.rectangle").font(.system(size:45)).foregroundStyle(.mint) } }.frame(height:145).frame(maxWidth:.infinity).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
                        Text(item.url.lastPathComponent).font(.system(size:11,weight:.medium)).lineLimit(1)
                        Text(item.date,style:.date).font(.system(size:10)).foregroundStyle(.secondary)
                        HStack { Button("Apri") { NSWorkspace.shared.open(item.url) }; if ["mov","mp4","m4v"].contains(item.url.pathExtension.lowercased()) { Button("Cornice") { model.selectVideo(item.url) } }; Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }; ShareLink(item:item.url) { Image(systemName:"square.and.arrow.up") } }.controlSize(.small)
                    }.padding(13).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:15))
                }
            }.padding(25)
        }
    }
    private var guide: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:25) {
                Text("Pronto per il tuo prossimo take.").font(.system(size:30,weight:.medium))
                guideCard("01",title:"iPhone e iPad via USB",text:"Usa un cavo dati, sblocca il dispositivo e tocca Autorizza quando richiesto. Premi Rileva USB, seleziona il dispositivo e Connetti. Consenti l’accesso Fotocamera: macOS tratta lo schermo iOS come una sorgente di acquisizione. Se il dispositivo è occupato, chiudi QuickTime o altre app di acquisizione.")
                guideCard("02",title:"iPhone e iPad in wireless",text:"Premi Wireless e consenti Rete locale se richiesto. Sul dispositivo apri Centro di Controllo → Duplica schermo → Specchio Studio. Inserisci il codice mostrato nell’app quando richiesto. Il video appare nello Studio mentre il Mac rimane utilizzabile. Usa la stessa rete Wi-Fi; non selezionare il nome del Mac, che attiva il ricevitore a schermo intero di macOS. Finestra / schermo resta disponibile per Simulator e altre finestre.")
                Button("Apri impostazioni AirDrop e Handoff") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")!) }
                guideCard("03",title:"Registrazione e creazione",text:"Registra salva il video originale in MOV H.264 o HEVC con l’audio della sorgente quando disponibile. Blocca un fotogramma per annotarlo; esporta lo screenshot con rotazione, cornice e sfondo, o copia il testo con OCR. Scegli un formato verticale 9:16, quadrato 1:1 o orizzontale 16:9 per preparare screenshot e video da condividere. Incornicia video applica in un secondo momento sfondo, cornice, rotazione e specchio ed eventualmente ritaglia l’intervallo temporale. Una nuova finestra dal menu File permette di lavorare con un altro dispositivo.")
                guideCard("04",title:"Controllo remoto",text:"Questa versione non implementa il controllo Bluetooth di iPhone/iPad. Per iPhone puoi aprire l’app Duplicazione iPhone di Apple, se disponibile nel tuo paese e compatibile con i tuoi dispositivi, e selezionarne la finestra come sorgente. Per iPad non viene offerto controllo remoto da Specchio.")
                Button("Apri Duplicazione iPhone di Apple") { let url = URL(fileURLWithPath:"/System/Applications/iPhone Mirroring.app"); if FileManager.default.fileExists(atPath:url.path) { NSWorkspace.shared.open(url) } else { model.tell("App Duplicazione iPhone non presente su questo Mac") } }
                guideCard("05",title:"Permessi e riservatezza",text:"Specchio elabora immagini, video e testo sul Mac. Non usa servizi cloud né richiede un account. I permessi vengono richiesti solo all’avvio della sorgente. Il contenuto protetto potrebbe non essere acquisibile. I collegamenti fisici e AirPlay vanno verificati con i tuoi dispositivi.")
                guideCard("06",title:"Segnalazioni, privacy e pacchetti creator",text:"Oscura dati blocca un fotogramma e permette di coprire aree con rettangoli opachi; il rilevamento locale suggerisce dati sensibili da verificare. Crea segnalazione bug salva immagini, testo OCR e descrizione in una cartella; l’originale non oscurato è escluso per impostazione iniziale. Pacchetto creator genera tre formati e una copertina. Puoi salvare lo stile per riutilizzarlo. Nei video le maschere coprono aree fisse per l’intera clip: controlla che i dati non si spostino. Le registrazioni originali e l’audio non vengono oscurati.")
                Text("Software libero distribuito con licenza GPL-3.0-or-later. Le dipendenze conservano le rispettive licenze; le informative sono disponibili nel menu Aiuto → Licenze open source.").font(.system(size:11)).foregroundStyle(.secondary)
            }.frame(maxWidth:760,alignment:.leading).padding(40)
        }
    }
    private func guideCard(_ number: String,title: String,text: String) -> some View {
        HStack(alignment:.top,spacing:20) { Text(number).font(.system(size:17,design:.monospaced)).foregroundStyle(.mint); VStack(alignment:.leading,spacing:9) { Text(title).font(.system(size:17,weight:.semibold)); Text(text).font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(5) } }
    }
}

struct SourceControls: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var engine: CaptureEngine
    @ObservedObject var screen: ScreenSource
    init(model: StudioModel) { self.model = model; engine = model.engine; screen = model.screen }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("SORGENTI").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary)
            if engine.devices.isEmpty { Label("Nessun dispositivo USB",systemImage:"iphone.slash").font(.system(size:11)).foregroundStyle(.secondary) }
            else { Picker("Dispositivo",selection:$model.selectedDevice) { Text("Seleziona…").tag(""); ForEach(engine.devices) { d in Text(d.name).tag(d.id) } }.labelsHidden() }
            HStack {
                Button(engine.isDiscovering ? "Rilevo…" : "Rileva USB") { Task { await engine.authorizeAndRefreshDevices() } }
                    .disabled(engine.isDiscovering)
                    .help("Richiede l’accesso Fotocamera necessario a macOS per rilevare lo schermo iOS")
                Button("Connetti") { model.connect() }.disabled(model.selectedDevice.isEmpty || engine.isRecording || engine.isFinalizing)
            }.controlSize(.small)
            Button { model.startWireless() } label: {
                Label(model.wireless.isStarting ? "Avvio…" : model.wireless.isListening ? "Wireless attivo" : "Wireless",systemImage:"wifi")
            }.disabled(engine.isRecording || engine.isFinalizing || model.wireless.isStarting || model.wireless.isListening)
            if model.wireless.isListening || model.wireless.isStarting {
                Text(model.wireless.status).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !model.wireless.pairingCode.isEmpty {
                    Text(model.wireless.pairingCode).font(.system(size:28,weight:.bold,design:.monospaced)).foregroundStyle(.mint).textSelection(.enabled)
                }
            }
            if let error=model.wireless.errorMessage { Text(error).font(.system(size:10)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            Button { model.pickScreen() } label: { Label("Finestra / schermo",systemImage:"macwindow") }.disabled(engine.isRecording || engine.isFinalizing)
            if engine.isRunning || screen.isActive || model.wireless.isListening || model.wireless.isStarting { Button("Disconnetti") { model.disconnect() }.controlSize(.small) }
            Text("USB / Wireless · iPhone / iPad\nSchermo · Simulator / finestre").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(4)
        }.buttonStyle(.bordered)
    }
}

struct CaptureToolbar: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var engine: CaptureEngine
    init(model: StudioModel) { self.model = model; engine = model.engine }
    var body: some View {
        HStack(spacing:12) {
            Circle().fill(engine.isRunning ? Color.mint : Color.gray).frame(width:6,height:6)
            Text(model.imported != nil ? "IMMAGINE APERTA" : model.demo ? "DEMO · ANTEPRIMA" : model.frozen != nil ? "FERMO IMMAGINE" : engine.isRunning ? "LIVE" : model.wireless.isListening ? "IN ATTESA · WIRELESS" : "STANDBY").font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1)
            if engine.isRecording { TimelineView(.periodic(from:.now,by:1)) { context in Text(elapsed(context.date)).font(.system(size:11,design:.monospaced)).foregroundStyle(.red) } }
            Spacer()
            Button { model.freeze() } label: { Image(systemName:model.frozen == nil ? "pause" : "play.fill") }.disabled(!engine.isRunning || model.imported != nil).help("Blocca / riprendi fotogramma")
            Button { model.exportImage() } label: { Image(systemName:"camera") }.disabled(model.image == nil && !model.demo).help("Esporta screenshot")
            Button { model.record() } label: { Label(model.countdown > 0 ? "Annulla" : engine.isRecording ? "Stop" : "Registra",systemImage:engine.isRecording ? "stop.fill" : "record.circle") }.tint(engine.isRecording ? .red : .mint).disabled(!engine.isRunning || engine.isFinalizing || model.recordBusy).keyboardShortcut("r",modifiers:[.command,.shift])
        }.font(.system(size:11)).buttonStyle(.bordered).controlSize(.small).padding(15)
    }
    func elapsed(_ now: Date) -> String { let n = Int(now.timeIntervalSince(model.recordingStart ?? now)); return String(format:"%02d:%02d",n/60,n%60) }
}

struct StatusFooter: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var engine: CaptureEngine
    @ObservedObject var screen: ScreenSource
    init(model: StudioModel) { self.model = model; engine = model.engine; screen = model.screen }
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:(engine.errorMessage != nil || screen.errorMessage != nil) ? "exclamationmark.circle" : "circle.dotted")
            Text(model.notification.isEmpty ? (engine.errorMessage ?? screen.errorMessage ?? (screen.isActive ? screen.status : engine.status)) : model.notification).lineLimit(2).textSelection(.enabled)
            Spacer()
            if engine.frameSize.width > 0 { Text("\(Int(engine.frameSize.width)) × \(Int(engine.frameSize.height))  ·  \(Int(engine.framesPerSecond)) fps").font(.system(size:9,design:.monospaced)) }
            if engine.isRunning { Image(systemName:engine.hasAudio ? "speaker.wave.2" : "speaker.slash").help(engine.hasAudio ? "Audio della sorgente incluso nella registrazione" : "Audio della sorgente non configurato") }
            Text("LOCAL STUDIO").font(.system(size:9,design:.monospaced)).tracking(1)
        }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,20).padding(.vertical,11).background(.white.opacity(0.025))
    }
}

struct WindowReader: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { if let w = view.window { callback(w) } }; return view }
    func updateNSView(_ nsView: NSView,context: Context) { }
}
