// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import Vision

struct BugReportDraft {
    var title = ""
    var steps = ""
    var expected = ""
    var actual = ""
    var appVersion = ""
    var deviceLabel = ""
    var includeOriginal = false
}

enum BugReportError: LocalizedError {
    case missingTitle
    case unreadableImage
    case destinationIsNotDirectory
    case textRecognitionFailed

    var errorDescription: String? {
        switch self {
        case .missingTitle: return "Aggiungi un titolo alla segnalazione."
        case .unreadableImage: return "Impossibile preparare le immagini della segnalazione."
        case .destinationIsNotDirectory: return "Scegli una cartella di destinazione valida."
        case .textRecognitionFailed: return "Impossibile leggere il testo dell’immagine. La segnalazione non è stata esportata."
        }
    }
}

@MainActor
enum BugReportExporter {
    /// `annotated` must already contain the privacy masks in the final composition.
    /// OCR always reads the separately redacted source, even when the user opts in
    /// to exporting the unredacted original.
    static func export(draft: BugReportDraft, original: NSImage, annotated: NSImage,
                       privacyMasks: [PrivacyMask], directory: URL) async throws -> URL {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw BugReportError.missingTitle }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BugReportError.destinationIsNotDirectory
        }
        try Task.checkCancellation()
        guard let sanitized = PrivacyRenderer.redactedImage(original, masks: privacyMasks) else {
            throw BugReportError.unreadableImage
        }
        let screenshotData = try pngData(sanitized)
        let annotatedData = try pngData(annotated)
        // Do not encode or read the unredacted image unless the user chose it.
        let originalData = draft.includeOriginal ? try pngData(original) : nil
        let ocrText: String
        do {
            ocrText = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(data: screenshotData).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
        } catch { throw BugReportError.textRecognitionFailed }
        try Task.checkCancellation()

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let identifier = UUID().uuidString.lowercased()
        let folderName = "Specchio-report-\(safeTitle(title))-\(identifier)"
        let destination = directory.appendingPathComponent(folderName, isDirectory: true)
        let staging = directory.appendingPathComponent(".specchio-report-\(identifier).tmp", isDirectory: true)
        // Staging stays on the same volume: the final move publishes the complete
        // report in one operation. Neither a prior report nor a user's files are
        // ever removed or replaced.
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: staging) } }

        try screenshotData.write(to: staging.appendingPathComponent("screenshot.png"), options: .atomic)
        try annotatedData.write(to: staging.appendingPathComponent("annotated.png"), options: .atomic)
        try Data(ocrText.utf8).write(to: staging.appendingPathComponent("OCR.txt"), options: .atomic)
        if let originalData {
            try originalData.write(to: staging.appendingPathComponent("original.png"), options: .atomic)
        }
        try Data(markdown(draft: draft, createdAt: createdAt, maskCount: privacyMasks.count).utf8)
            .write(to: staging.appendingPathComponent("report.md"), options: .atomic)
        let manifest = Manifest(
            schemaVersion: 1, createdAt: createdAt,
            title: title, steps: draft.steps, expected: draft.expected, actual: draft.actual,
            appVersion: draft.appVersion, deviceLabel: draft.deviceLabel,
            files: Files(screenshot: "screenshot.png", annotated: "annotated.png", ocr: "OCR.txt",
                         original: draft.includeOriginal ? "original.png" : nil),
            privacy: Privacy(maskCount: privacyMasks.count, originalIncluded: draft.includeOriginal,
                             ocrSource: "screenshot.png", reviewNote: privacyReview)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: staging.appendingPathComponent("report.json"), options: .atomic)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
        published = true
        return destination
    }

    private static let privacyReview = "Controlla immagini, testo OCR e descrizione prima di condividere. Le maschere coprono solo le aree selezionate e non rilevano automaticamente tutti i dati sensibili."

    private struct Manifest: Encodable {
        let schemaVersion: Int
        let createdAt: String
        let title: String
        let steps: String
        let expected: String
        let actual: String
        let appVersion: String
        let deviceLabel: String
        let files: Files
        let privacy: Privacy
    }

    private struct Files: Encodable {
        let screenshot: String
        let annotated: String
        let ocr: String
        let original: String?
    }

    private struct Privacy: Encodable {
        let maskCount: Int
        let originalIncluded: Bool
        let ocrSource: String
        let reviewNote: String
    }

    private static func safeTitle(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let safe = folded.unicodeScalars.map { scalar -> Character in
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                return Character(String(scalar))
            }
            return "-"
        }
        let words = String(safe).split(separator: "-").joined(separator: "-")
        let short = String(words.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return short.isEmpty ? "segnalazione" : short
    }

    private static func pngData(_ image: NSImage) throws -> Data {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0,
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw BugReportError.unreadableImage
        }
        return data
    }

    private static func markdownText(_ value: String) -> String {
        var escaped = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for character in ["\\", "`", "*", "_", "[", "]", "<", ">", "#", "!", "|"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\" + character)
        }
        return escaped.isEmpty ? "—" : escaped
    }

    private static func markdown(draft: BugReportDraft, createdAt: String, maskCount: Int) -> String {
        let title = draft.title.components(separatedBy: .newlines).joined(separator: " ")
        let originalNotice = draft.includeOriginal
            ? "ATTENZIONE: [original.png](original.png) è incluso senza maschere privacy per scelta esplicita. Può contenere dati sensibili."
            : "Il file separato original.png non è incluso. Screenshot e composizione contengono solo le maschere selezionate: con zero maschere i dati rimangono visibili."
        return """
        # \(markdownText(title))

        Creato con Specchio Studio · \(createdAt)

        ## Riproduzione

        \(markdownText(draft.steps))

        ## Risultato atteso

        \(markdownText(draft.expected))

        ## Risultato osservato

        \(markdownText(draft.actual))

        ## Contesto inserito dall’autore

        - Versione dell’app: \(markdownText(draft.appVersion))
        - Dispositivo / ambiente: \(markdownText(draft.deviceLabel))

        ## Allegati

        - [Screenshot con maschere privacy applicate](screenshot.png)
        - [Composizione annotata](annotated.png)
        - [Testo OCR dello screenshot con maschere applicate](OCR.txt)
        - [Dati strutturati della segnalazione](report.json)

        ## Verifica prima della condivisione

        \(privacyReview)

        Maschere selezionate: \(maskCount). L’OCR è stato calcolato esclusivamente da screenshot.png, dopo l’applicazione delle maschere.

        \(originalNotice)

        Il contesto è stato inserito manualmente. Il pacchetto non raccoglie automaticamente identificativi del dispositivo, nomi host o percorsi dei file sorgenti. Nessun file è stato inviato a servizi esterni.
        """ + "\n"
    }
}

struct BugReportSheet: View {
    let original: NSImage
    let annotated: NSImage
    let privacyMasks: [PrivacyMask]
    let onComplete: (URL) -> Void
    let onCancel: () -> Void
    let onBusyChange: (Bool) -> Void
    @StoredState private var draft = BugReportDraft()
    @StoredState private var isExporting = false
    @StoredState private var errorMessage: String?
    @StoredState private var exportTask: Task<Void, Never>?

    init(original: NSImage, annotated: NSImage, privacyMasks: [PrivacyMask],
         onComplete: @escaping (URL) -> Void, onCancel: @escaping () -> Void,
         onBusyChange: @escaping (Bool) -> Void = { _ in }) {
        self.original = original
        self.annotated = annotated
        self.privacyMasks = privacyMasks
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.onBusyChange = onBusyChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crea una segnalazione bug").font(.system(size: 23, weight: .semibold))
            Text("Raccogli screenshot, annotazioni, testo OCR e istruzioni in una cartella pronta da allegare.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(nsImage: annotated).resizable().scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 310)
                            .background(.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Anteprima della composizione allegata")
                        Text(privacyMasks.count == 1 ? "1 maschera privacy applicata allo screenshot. L’OCR legge lo screenshot oscurato." : "\(privacyMasks.count) maschere privacy applicate allo screenshot. L’OCR legge lo screenshot oscurato.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Controlla tutti gli allegati prima di condividerli: le maschere coprono solo le aree che hai selezionato.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(width: 240)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Titolo della segnalazione", text: $draft.title).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Titolo della segnalazione")
                        editor("Passaggi per riprodurre", text: $draft.steps)
                        editor("Risultato atteso", text: $draft.expected)
                        editor("Risultato osservato", text: $draft.actual)
                        TextField("Versione dell’app (facoltativa)", text: $draft.appVersion).textFieldStyle(.roundedBorder)
                        TextField("Dispositivo / ambiente (facoltativo)", text: $draft.deviceLabel).textFieldStyle(.roundedBorder)
                        Text("Inserisci soltanto il contesto utile. Evita password, token, numeri di serie e dati personali.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }.frame(maxHeight: 430)
            Toggle("Includi anche original.png senza maschere privacy", isOn: $draft.includeOriginal)
                .font(.system(size: 12))
            Text(draft.includeOriginal
                 ? "L’originale non oscurato sarà aggiunto alla cartella e potrebbe rivelare i dati coperti nelle altre immagini. L’OCR continuerà a usare solo lo screenshot oscurato."
                 : "Il file original.png è escluso. Le altre immagini includeranno solo le maschere selezionate: con zero maschere i dati restano visibili.")
                .font(.system(size: 11)).foregroundStyle(draft.includeOriginal ? .orange : .secondary)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                if isExporting { ProgressView().controlSize(.small); Text("Preparazione immagini e OCR…").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction).disabled(isExporting)
                Button("Esporta segnalazione…", action: chooseDestination).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26).frame(width: 780)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isExporting)
        .onDisappear { exportTask?.cancel() }
    }

    private func editor(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium))
            TextEditor(text: text).font(.system(size: 12)).frame(height: 54)
                .padding(4).background(.black.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(label)
        }
    }

    @MainActor private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Scegli dove salvare la segnalazione"
        panel.message = "Verrà creata una nuova cartella con tutti gli allegati. Nessun file verrà inviato."
        panel.prompt = "Scegli cartella"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        isExporting = true
        onBusyChange(true)
        errorMessage = nil
        let snapshot = draft
        exportTask = Task { @MainActor in
            defer { isExporting = false; onBusyChange(false); exportTask = nil }
            do {
                let result = try await BugReportExporter.export(draft: snapshot, original: original, annotated: annotated,
                                                                privacyMasks: privacyMasks, directory: directory)
                onComplete(result)
            } catch is CancellationError {
                // Closing the window cancels only our staging directory. No
                // half-written report is made visible at the destination.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
