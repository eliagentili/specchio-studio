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
        case .missingTitle: return L("Aggiungi un titolo alla segnalazione.")
        case .unreadableImage: return L("Impossibile preparare le immagini della segnalazione.")
        case .destinationIsNotDirectory: return L("Scegli una cartella di destinazione valida.")
        case .textRecognitionFailed: return L("Impossibile leggere il testo dell’immagine. La segnalazione non è stata esportata.")
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

    private static let privacyReview = "Review images, OCR text, and the description before sharing. Masks cover only selected areas and do not automatically detect all sensitive data."

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
        return short.isEmpty ? "report" : short
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
            ? "WARNING: [original.png](original.png) is included without privacy masks by explicit choice. It may contain sensitive data."
            : "The separate original.png file is not included. Screenshots and compositions contain only the selected masks: with no masks, data remains visible."
        return """
        # \(markdownText(title))

        Created with Specchio Studio · \(createdAt)

        ## Steps to reproduce

        \(markdownText(draft.steps))

        ## Expected result

        \(markdownText(draft.expected))

        ## Actual result

        \(markdownText(draft.actual))

        ## Context supplied by the author

        - App version: \(markdownText(draft.appVersion))
        - Device / environment: \(markdownText(draft.deviceLabel))

        ## Attachments

        - [Screenshot with privacy masks applied](screenshot.png)
        - [Annotated composition](annotated.png)
        - [OCR text from the masked screenshot](OCR.txt)
        - [Structured report data](report.json)

        ## Review before sharing

        \(privacyReview)

        Selected masks: \(maskCount). OCR was generated exclusively from screenshot.png, after masks were applied.

        \(originalNotice)

        Context was entered manually. The bundle does not automatically collect device identifiers, host names, or source file paths. No files were sent to external services.
        """ + "\n"
    }
}

struct BugReportSheet: View {
    @ObservedObject private var localization = AppLocalization.shared
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
            Text(L("Crea una segnalazione bug")).font(.system(size: 23, weight: .semibold))
            Text(L("Raccogli screenshot, annotazioni, testo OCR e istruzioni in una cartella pronta da allegare."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(nsImage: annotated).resizable().scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 310)
                            .background(.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(L("Anteprima della composizione allegata"))
                        Text(privacyMasks.count == 1 ? L("1 maschera privacy applicata allo screenshot. L’OCR legge lo screenshot oscurato.") : LF("%d maschere privacy applicate allo screenshot. L’OCR legge lo screenshot oscurato.", privacyMasks.count))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(L("Controlla tutti gli allegati prima di condividerli: le maschere coprono solo le aree che hai selezionato."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(width: 240)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L("Titolo della segnalazione"), text: $draft.title).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L("Titolo della segnalazione"))
                        editor(L("Passaggi per riprodurre"), text: $draft.steps)
                        editor(L("Risultato atteso"), text: $draft.expected)
                        editor(L("Risultato osservato"), text: $draft.actual)
                        TextField(L("Versione dell’app (facoltativa)"), text: $draft.appVersion).textFieldStyle(.roundedBorder)
                        TextField(L("Dispositivo / ambiente (facoltativo)"), text: $draft.deviceLabel).textFieldStyle(.roundedBorder)
                        Text(L("Inserisci soltanto il contesto utile. Evita password, token, numeri di serie e dati personali."))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }.frame(maxHeight: 430)
            Toggle(L("Includi anche original.png senza maschere privacy"), isOn: $draft.includeOriginal)
                .font(.system(size: 12))
            Text(draft.includeOriginal
                 ? L("L’originale non oscurato sarà aggiunto alla cartella e potrebbe rivelare i dati coperti nelle altre immagini. L’OCR continuerà a usare solo lo screenshot oscurato.")
                 : L("Il file original.png è escluso. Le altre immagini includeranno solo le maschere selezionate: con zero maschere i dati restano visibili."))
                .font(.system(size: 11)).foregroundStyle(draft.includeOriginal ? .orange : .secondary)
            if let errorMessage {
                Text(L(errorMessage)).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                if isExporting { ProgressView().controlSize(.small); Text(L("Preparazione immagini e OCR…")).font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button(L("Annulla"), action: onCancel).keyboardShortcut(.cancelAction).disabled(isExporting)
                Button(L("Esporta segnalazione…"), action: chooseDestination).buttonStyle(.borderedProminent)
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
        panel.title = L("Scegli dove salvare la segnalazione")
        panel.message = L("Verrà creata una nuova cartella con tutti gli allegati. Nessun file verrà inviato.")
        panel.prompt = L("Scegli cartella")
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
