// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Vision

@MainActor
enum BugReportTests {
    static func run(directory: URL) async throws {
        let root = directory.appendingPathComponent("bug-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let original = fixture()
        let masks = [PrivacyMask(rect: CGRect(x: 0, y: 0, width: 1, height: 0.60))]
        guard let sanitized = PrivacyRenderer.redactedImage(original, masks: masks) else {
            fatalError("Bug report test could not redact the fixture")
        }
        let baselineRequest = VNRecognizeTextRequest()
        baselineRequest.recognitionLevel = .accurate
        try VNImageRequestHandler(data: png(original)).perform([baselineRequest])
        let baselineText = (baselineRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased()
        guard baselineText.contains("example.com") else {
            fatalError("Bug report privacy fixture must contain readable private text: \(baselineText)")
        }

        var draft = BugReportDraft()
        draft.title = "Apertura schermata"
        draft.steps = "1. Apri la schermata\n2. Tocca Continua"
        draft.expected = "La schermata successiva si apre"
        draft.actual = "Il pulsante resta inattivo"
        draft.appVersion = "1.2.0"
        draft.deviceLabel = "Dispositivo sintetico"
        guard !draft.includeOriginal else { fatalError("Unredacted original must be opt-in") }
        let first = try await BugReportExporter.export(draft: draft, original: original, annotated: sanitized,
                                                        privacyMasks: masks, directory: root)
        let expectedFiles: Set<String> = ["screenshot.png", "annotated.png", "OCR.txt", "report.md", "report.json"]
        guard Set(try FileManager.default.contentsOfDirectory(atPath: first.path)) == expectedFiles else {
            fatalError("Default bug report includes unexpected files or an unredacted original")
        }
        let textFiles = try ["OCR.txt", "report.md", "report.json"].map {
            try String(contentsOf: first.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n").lowercased()
        guard !textFiles.contains("private.person"), !textFiles.contains("example.com"), !textFiles.contains(root.path.lowercased()) else {
            fatalError("Default bug report leaked masked text or a source path")
        }
        let ocr = try String(contentsOf: first.appendingPathComponent("OCR.txt"), encoding: .utf8)
        guard ocr.contains("PUBLIC CHECK") else { fatalError("Bug report OCR did not read unmasked text: \(ocr)") }
        let screenshot = try Data(contentsOf: first.appendingPathComponent("screenshot.png"))
        guard screenshot == png(sanitized), screenshot != png(original) else {
            fatalError("Bug report screenshot did not contain the applied masks")
        }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: first.appendingPathComponent("report.json"))) as? [String: Any]
        let privacy = json?["privacy"] as? [String: Any]
        let files = json?["files"] as? [String: Any]
        guard privacy?["originalIncluded"] as? Bool == false,
              privacy?["ocrSource"] as? String == "screenshot.png", files?["original"] == nil else {
            fatalError("Default report manifest misstates privacy behavior")
        }
        print("PASS: bug report defaults omit unredacted original and OCR excludes masked email")

        draft.includeOriginal = true
        let optedIn = try await BugReportExporter.export(draft: draft, original: original, annotated: sanitized,
                                                          privacyMasks: masks, directory: root)
        guard try Data(contentsOf: optedIn.appendingPathComponent("original.png")) == png(original) else {
            fatalError("Opt-in report did not preserve the original image content")
        }
        let optedInOCR = try String(contentsOf: optedIn.appendingPathComponent("OCR.txt"), encoding: .utf8).lowercased()
        guard !optedInOCR.contains("example.com") else { fatalError("Opt-in original changed the safe OCR source") }
        let optedInMarkdown = try String(contentsOf: optedIn.appendingPathComponent("report.md"), encoding: .utf8)
        guard optedInMarkdown.contains("senza maschere privacy per scelta esplicita") else {
            fatalError("Opt-in report lacks the unredacted original disclosure")
        }
        print("PASS: explicit original opt-in preserves image and keeps OCR redacted")

        let marker = first.appendingPathComponent("review-marker.txt")
        try Data("Keep existing report".utf8).write(to: marker)
        draft.includeOriginal = false
        let duplicateTitle = try await BugReportExporter.export(draft: draft, original: original, annotated: sanitized,
                                                                 privacyMasks: masks, directory: root)
        guard duplicateTitle != first, duplicateTitle != optedIn,
              try String(contentsOf: marker, encoding: .utf8) == "Keep existing report",
              try Data(contentsOf: first.appendingPathComponent("screenshot.png")) == screenshot else {
            fatalError("Repeated report export overwrote an existing report")
        }

        draft.title = "../../outside/../.hidden\\title\n<&>"
        let traversal = try await BugReportExporter.export(draft: draft, original: original, annotated: sanitized,
                                                            privacyMasks: masks, directory: root)
        guard traversal.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              !traversal.lastPathComponent.contains(".."), !traversal.lastPathComponent.contains("/") else {
            fatalError("Report title escaped the selected directory")
        }
        guard !(try FileManager.default.contentsOfDirectory(atPath: root.path)).contains(where: { $0.hasPrefix(".specchio-report-") }) else {
            fatalError("Completed report left a staging directory behind")
        }
        print("PASS: unique bug report folders preserve existing files and sanitize traversal titles")
    }

    private static func png(_ image: NSImage) -> Data {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fatalError("Could not encode the synthetic report fixture")
        }
        return data
    }

    private static func fixture() -> NSImage {
        let image = NSImage(size: CGSize(width: 1000, height: 600))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "private.person@example.com").draw(at: CGPoint(x: 35, y: 440), withAttributes: attributes)
        NSString(string: "PUBLIC CHECK").draw(at: CGPoint(x: 35, y: 75), withAttributes: attributes)
        image.unlockFocus()
        return image
    }
}
