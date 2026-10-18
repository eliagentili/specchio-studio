import SwiftUI
import AVKit

struct VideoExportSheet: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: StudioModel
    @ObservedObject var exporter: VideoExporter
    @ObservedObject var creatorExporter: CreatorExport
    @StoredState private var player = AVPlayer()
    @StoredState private var privacyFrame: NSImage?
    @StoredState private var showPrivacyEditor = false
    @StoredState private var frameError: String?
    @StoredState private var loadingFrame = false
    init(model:StudioModel) { self.model = model; exporter = model.exporter; creatorExporter = model.creatorExporter }
    private var exporting: Bool { exporter.isExporting || creatorExporter.isExporting }
    private var validTrim: Bool {
        model.trimStart.isFinite && model.trimEnd.isFinite && model.trimStart >= 0 && model.trimEnd >= 0 &&
            (model.trimEnd == 0 || model.trimEnd > model.trimStart)
    }
    private var formatDescription: String {
        if let size = model.compositionFormat.exportSize {
            return LF("%d × %d px, senza tagliare il video originale.", Int(size.width), Int(size.height))
        }
        return L("Formato ricavato dal video originale, con spazio per cornice e sfondo.")
    }
    var body: some View {
        ScrollView {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:7) { Text(L("Un video, pronto da presentare.")).font(.system(size:23,weight:.semibold)); Text(model.videoSource?.lastPathComponent ?? L("Video")).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1) }; Spacer() }
            Group {
                if !model.videoPrivacyMasks.isEmpty {
                    if let image = privacyFrame, let safeImage = PrivacyRenderer.redactedImage(image, masks: model.videoPrivacyMasks) {
                        Image(nsImage: safeImage).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity)
                    } else { Text(L("Anteprima privacy non disponibile")).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                } else { NativeVideoPreview(player:player) }
            }.frame(height:170).clipShape(RoundedRectangle(cornerRadius:12))
            Text(model.videoPrivacyMasks.isEmpty ? L("Anteprima del file originale. La composizione viene applicata all’esportazione.") : L("Primo fotogramma sorgente con privacy; rotazione, cornice e sfondo vengono applicati all’esportazione.")).font(.system(size:10)).foregroundStyle(.secondary)
            HStack {
                Button(model.videoPrivacyMasks.isEmpty ? L("Oscura dati sensibili…") : LF("Modifica %d maschere…", model.videoPrivacyMasks.count)) {
                    player.pause(); showPrivacyEditor = true
                }.disabled(exporting || loadingFrame || privacyFrame == nil)
                if loadingFrame { ProgressView().controlSize(.small) }
                if !model.videoPrivacyMasks.isEmpty {
                    Button(L("Rimuovi maschere")) { model.videoPrivacyMasks = [] }.disabled(exporting)
                }
            }.font(.system(size:11))
            if let frameError { Text(L(frameError)).font(.system(size:11)).foregroundStyle(.orange) }
            if !model.videoPrivacyMasks.isEmpty {
                Text(L("Le maschere sono aree fisse per tutto il taglio, non seguono il contenuto. Controlla tutti i fotogrammi prima di condividere.")).font(.system(size:11)).foregroundStyle(.secondary)
            }
            Picker(L("Formato di uscita"),selection:$model.compositionFormat) {
                ForEach(CompositionFormat.allCases) { Text(L($0.rawValue)).tag($0) }
            }.disabled(exporting)
            Text(formatDescription).font(.system(size:11)).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:25) {
                VStack(alignment:.leading,spacing:14) {
                    Picker(L("Sfondo"),selection:$model.backdrop) { ForEach(Backdrop.allCases) { Text(L($0.rawValue)).tag($0) } }
                    Toggle(L("Cornice dispositivo"),isOn:$model.showFrame)
                    Toggle(L("Specchia orizzontalmente"),isOn:$model.flipped)
                }
                VStack(alignment:.leading,spacing:14) {
                    Picker(L("Rotazione"),selection:$model.rotation) { Text("0°").tag(0); Text("90°").tag(1); Text("180°").tag(2); Text("270°").tag(3) }
                    HStack { Text(L("Inizio (s)")); VideoSecondsField(title:L("Inizio in secondi"),value:$model.trimStart).frame(width:80) }
                    HStack { Text(L("Fine (s)")); VideoSecondsField(title:L("Fine in secondi"),value:$model.trimEnd).frame(width:80) }
                }
            }.font(.system(size:12)).disabled(exporting)
            HStack { Text(L("Titolo copertina")); TextField(L("Facoltativo, per il pacchetto creator"),text:$model.creatorTitle) }.font(.system(size:12)).disabled(exporting)
            Text(L("MOV H.264, massimo 1920 px per lato, audio originale. Fine = 0 esporta fino al termine. Lo sfondo Trasparente viene reso nero nei video; le annotazioni sono disponibili per gli screenshot.")).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
            if !validTrim { Text(L("Usa tempi positivi, con Fine maggiore di Inizio oppure uguale a 0.")).font(.system(size:11)).foregroundStyle(.orange) }
            if exporter.isExporting { ProgressView(value:Double(exporter.progress)); Text(LF("Esportazione %d%%", Int(Double(exporter.progress)*100))).font(.system(size:11,design:.monospaced)) }
            if creatorExporter.isExporting { ProgressView(value:creatorExporter.progress); Text(LF("Pacchetto creator %d%% · tre formati e copertina", Int(creatorExporter.progress*100))).font(.system(size:11,design:.monospaced)) }
            if let error = exporter.errorMessage { Text(L(error)).font(.system(size:11)).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = creatorExporter.errorMessage { Text(L(error)).font(.system(size:11)).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button(exporting ? L("Annulla esportazione") : L("Chiudi")) { if exporting { exporter.cancel(); creatorExporter.cancel() } else { model.showVideoExport = false } }
                Spacer()
                Button(L("Pacchetto creator")) { player.pause(); model.exportCreatorVideo() }.disabled(exporting || !validTrim)
                Button(L("Esporta video")) { player.pause(); model.exportVideo() }.buttonStyle(.borderedProminent).disabled(exporting || !validTrim)
            }
        }.padding(28)
        }.frame(width:620).frame(maxHeight:min(820,max(520,(NSScreen.main?.visibleFrame.height ?? 940)-120))).preferredColorScheme(.dark)
        .interactiveDismissDisabled(exporting)
        .onAppear { if let url = model.videoSource { player.replaceCurrentItem(with:AVPlayerItem(url:url)) } }
        .onDisappear { player.pause(); player.replaceCurrentItem(with:nil) }
        .task(id: model.videoSource) { await preparePrivacyFrame() }
        .sheet(isPresented: $showPrivacyEditor) {
            if let privacyFrame {
                PrivacyEditorView(image: privacyFrame, masks: model.videoPrivacyMasks,
                                  onApply: { model.videoPrivacyMasks = $0; showPrivacyEditor = false },
                                  onCancel: { showPrivacyEditor = false })
            }
        }
    }

    @MainActor private func preparePrivacyFrame() async {
        privacyFrame = nil; frameError = nil
        guard let source = model.videoSource else { return }
        loadingFrame = true
        defer { loadingFrame = false }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        // All masks stay in raw source coordinates, independent of metadata or style.
        generator.appliesPreferredTrackTransform = false
        do {
            let frame = try await generator.image(at: .zero).image
            guard !Task.isCancelled, model.videoSource == source else { return }
            privacyFrame = NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height))
        } catch {
            if !Task.isCancelled { frameError = LF("Anteprima privacy non disponibile: %@", error.localizedDescription) }
        }
    }
}

enum VideoTrimTime {
    static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Keep the editing buffer intact while a decimal separator is being entered.
/// Invalid text disables export rather than silently reverting to the full clip.
struct VideoSecondsField: View {
    @ObservedObject private var localization = AppLocalization.shared
    let title: String
    @Binding var value: Double
    @StoredState private var text: String

    init(title: String, value: Binding<Double>) {
        self.title = title; _value = value
        _text = StoredState(initialValue:value.wrappedValue == 0 ? "0" : String(value.wrappedValue))
    }
    var body: some View {
        TextField("0",text:$text)
            .accessibilityLabel(title)
            .onChange(of:text) { _, updated in value = VideoTrimTime.parse(updated) ?? .nan }
    }
}

// AppKit's player avoids the SwiftUI VideoPlayer metadata issue in the
// command-line SDK shipped with this macOS build.
struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context:Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view:AVPlayerView,context:Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view:AVPlayerView,coordinator:()) { view.player?.pause(); view.player = nil }
}
