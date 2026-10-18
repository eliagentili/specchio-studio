import SwiftUI
import AppKit
import Vision

/// A rectangle in the untransformed source image. The origin is its top-left corner.
struct PrivacyMask: Identifiable, Codable, Equatable {
    var id: UUID
    private var normalizedRect: CGRect

    var rect: CGRect {
        get { normalizedRect }
        set { normalizedRect = Self.sanitized(newValue) }
    }

    var isUsable: Bool { rect.width > 0 && rect.height > 0 }

    init(id: UUID = UUID(), rect: CGRect) {
        self.id = id
        normalizedRect = Self.sanitized(rect)
    }

    private static func sanitized(_ rect: CGRect) -> CGRect {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return .zero }
        let value = rect.standardized
        let left = min(1, max(0, value.minX))
        let top = min(1, max(0, value.minY))
        let right = min(1, max(0, value.maxX))
        let bottom = min(1, max(0, value.maxY))
        guard right > left, bottom > top else { return .zero }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private enum CodingKeys: String, CodingKey { case id, rect }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  rect: try container.decode(CGRect.self, forKey: .rect))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rect, forKey: .rect)
    }
}

enum PrivacyRenderer {
    /// AppKit resolves any representation and orientation before the same pixels are used by OCR,
    /// the editor, and the renderer. The returned CGImage retains the source's pixel dimensions.
    static func sourceCGImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Redaction is irreversible in the returned raster: covered source pixels become opaque black.
    /// It happens before composition transforms, so rotation and reflection also move the masks.
    static func redactedImage(_ image: NSImage, masks: [PrivacyMask]) -> NSImage? {
        let validMasks = masks.filter(\.isUsable)
        guard !validMasks.isEmpty else { return image }
        guard let source = sourceCGImage(image) else { return nil }
        let width = source.width
        let height = source.height
        guard width > 0, height > 0, width <= Int.max / 4,
              height <= Int.max / (width * 4) else { return nil }
        let bytesPerRow = width * 4
        let storage = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow * height, alignment: 16)
        defer { storage.deallocate() }
        let colorSpace = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: storage, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Write complete pixels, including alpha, and round outward. No blur, antialiasing,
        // overlay metadata, or recoverable source layer is included in the result.
        let pixels = storage.assumingMemoryBound(to: UInt8.self)
        for mask in validMasks {
            let left = max(0, min(width, Int(floor(mask.rect.minX * CGFloat(width)))))
            let right = max(0, min(width, Int(ceil(mask.rect.maxX * CGFloat(width)))))
            let top = max(0, min(height, Int(floor(mask.rect.minY * CGFloat(height)))))
            let bottom = max(0, min(height, Int(ceil(mask.rect.maxY * CGFloat(height)))))
            for y in top..<bottom {
                for x in left..<right {
                    let offset = y * bytesPerRow + x * 4
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 255
                }
            }
        }
        // Keep an independent immutable copy: a CGContext snapshot may share its backing buffer,
        // and the caller-owned scratch storage is released when this function returns.
        let raster = Data(bytes: storage, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: raster as CFData),
              let redacted = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: bytesPerRow, space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                        CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: redacted, size: image.size)
    }
}

struct PrivacySuggestion: Identifiable {
    enum Kind: String {
        case email = "Indirizzo email"
        case phone = "Numero di telefono"
        case card = "Numero di carta o identificativo"
        case token = "Possibile chiave o token"
    }

    let id = UUID()
    let mask: PrivacyMask
    let kind: Kind
}

enum PrivacyScanner {
    enum ScanError: Error { case unreadableImage }

    static func localTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "it-IT"]
        request.usesLanguageCorrection = false
        // CPU processing avoids a first-use Neural Engine model-compilation delay while this
        // small, explicit user action runs on a background queue. Use supported devices only.
        if let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        return request
    }

    /// Vision runs on this Mac. Recognized source strings are used only to locate suggestions;
    /// neither strings nor image data are logged, stored, or sent to a service.
    static func scan(_ image: NSImage) async throws -> [PrivacySuggestion] {
        guard let source = PrivacyRenderer.sourceCGImage(image) else { throw ScanError.unreadableImage }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = localTextRequest()
                    try VNImageRequestHandler(cgImage: source).perform([request])
                    var suggestions: [PrivacySuggestion] = []
                    for observation in request.results ?? [] {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        for match in sensitiveRanges(in: candidate.string) {
                            let box = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                            let paddingX = max(0.006, 3 / CGFloat(source.width))
                            let paddingY = max(0.003, 3 / CGFloat(source.height))
                            let topLeft = CGRect(x: box.minX, y: 1 - box.maxY,
                                                 width: box.width, height: box.height)
                                .insetBy(dx: -paddingX, dy: -paddingY)
                            let mask = PrivacyMask(rect: topLeft)
                            if mask.isUsable { suggestions.append(PrivacySuggestion(mask: mask, kind: match.kind)) }
                        }
                    }
                    continuation.resume(returning: suggestions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct SensitiveRange {
        let range: Range<String.Index>
        let kind: PrivacySuggestion.Kind
    }

    private static func sensitiveRanges(in text: String) -> [SensitiveRange] {
        let patterns: [(PrivacySuggestion.Kind, String)] = [
            (.token, #"(?:gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|(?:sk|pk)[-_](?:live|test)[-_][A-Za-z0-9]{12,}|sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|(?:api[_-]?key|token|secret)\s*[:=]\s*["']?[A-Za-z0-9_\-/.+=]{12,})"#),
            (.email, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}"#),
            (.card, #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#),
            (.phone, #"(?<![A-Z0-9])\+?\d[\d ()-]{5,}\d(?![A-Z0-9])"#)
        ]
        var accepted: [NSRange] = []
        var result: [SensitiveRange] = []
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: whole) {
                guard !accepted.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let range = Range(match.range, in: text) else { continue }
                if kind == .phone {
                    let digits = text[range].filter(\.isNumber).count
                    guard (8...15).contains(digits) else { continue }
                }
                accepted.append(match.range)
                result.append(SensitiveRange(range: range, kind: kind))
            }
        }
        return result
    }
}

struct PrivacyEditorView: View {
    @ObservedObject private var localization = AppLocalization.shared
    let image: NSImage
    let onApply: ([PrivacyMask]) -> Void
    let onCancel: () -> Void
    @StoredState private var masks: [PrivacyMask]
    @StoredState private var selectedMaskID: UUID?
    @StoredState private var dragStart: CGPoint?
    @StoredState private var dragEnd: CGPoint?
    @StoredState private var suggestions: [PrivacySuggestion] = []
    @StoredState private var selectedSuggestions: Set<UUID> = []
    @StoredState private var scanning = false
    @StoredState private var scanMessage: String?
    @StoredState private var scanTask: Task<Void, Never>?

    init(image: NSImage, masks: [PrivacyMask], onApply: @escaping ([PrivacyMask]) -> Void,
         onCancel: @escaping () -> Void) {
        self.image = image
        self.onApply = onApply
        self.onCancel = onCancel
        _masks = StoredState(initialValue: masks.filter(\.isUsable))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Oscura dati sensibili")).font(.title2.bold())
                    Text(L("Trascina sullo schermo per aggiungere maschere nere permanenti agli export."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label(L("Sul tuo Mac"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                editorCanvas
                    .frame(minWidth: 430, minHeight: 420)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                inspector.frame(width: 255)
            }
            HStack {
                Text(L("Controlla il risultato: il rilevamento automatico può non trovare tutti i dati."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Annulla"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(masks.count == 1 ? L("Applica 1 maschera") : LF("Applica %d maschere", masks.count)) { onApply(masks.filter(\.isUsable)) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 780, idealWidth: 920, minHeight: 560, idealHeight: 690)
        .onDisappear { scanTask?.cancel() }
    }

    private var editorCanvas: some View {
        GeometryReader { geometry in
            let pixels = PrivacyRenderer.sourceCGImage(image)
            let ratio = pixels.map { CGFloat($0.width) / CGFloat(max(1, $0.height)) } ?? image.size.width / max(1, image.size.height)
            let width = min(max(1, geometry.size.width - 28), max(1, geometry.size.height - 28) * ratio)
            let height = width / max(0.001, ratio)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: width, height: height)
                ForEach(masks) { mask in
                    Rectangle().fill(.black)
                        .overlay(Rectangle().stroke(selectedMaskID == mask.id ? Color.accentColor : .white.opacity(0.8), lineWidth: selectedMaskID == mask.id ? 2 : 1))
                        .frame(width: mask.rect.width * width, height: mask.rect.height * height)
                        .position(x: mask.rect.midX * width, y: mask.rect.midY * height)
                        .onTapGesture { selectedMaskID = mask.id }
                        .accessibilityLabel(L("Maschera di oscuramento"))
                }
                ForEach(suggestions.filter { selectedSuggestions.contains($0.id) }) { suggestion in
                    let rect = suggestion.mask.rect
                    Rectangle().fill(Color.orange.opacity(0.25))
                        .overlay(Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
                        .frame(width: rect.width * width, height: rect.height * height)
                        .position(x: rect.midX * width, y: rect.midY * height)
                        .allowsHitTesting(false)
                }
                if let pending = pendingMask {
                    Rectangle().fill(Color.black.opacity(0.8)).overlay(Rectangle().stroke(.white, lineWidth: 1))
                        .frame(width: pending.rect.width * width, height: pending.rect.height * height)
                        .position(x: pending.rect.midX * width, y: pending.rect.midY * height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                dragStart = normalized(value.startLocation, width: width, height: height)
                dragEnd = normalized(value.location, width: width, height: height)
            }.onEnded { value in
                dragEnd = normalized(value.location, width: width, height: height)
                if let mask = pendingMask, mask.isUsable {
                    masks.append(mask)
                    selectedMaskID = mask.id
                }
                dragStart = nil
                dragEnd = nil
            })
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LF("Maschere (%d)", masks.count)).font(.headline)
                Spacer()
                Button(L("Svuota")) { masks.removeAll(); selectedMaskID = nil }.disabled(masks.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if masks.isEmpty {
                        Text(L("Disegna un rettangolo sull’immagine, oppure analizza il testo."))
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(Array(masks.enumerated()), id: \.element.id) { index, mask in
                        HStack {
                            Button(LF("Maschera %d", index + 1)) { selectedMaskID = mask.id }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectedMaskID == mask.id ? Color.accentColor : Color.primary)
                            Spacer()
                            Button { masks.removeAll { $0.id == mask.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel(LF("Rimuovi maschera %d", index + 1))
                        }.padding(7).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }.frame(maxHeight: 195)
            Divider()
            Button { detect() } label: {
                HStack {
                    if scanning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "text.viewfinder") }
                    Text(scanning ? L("Analisi in corso…") : L("Rileva dati sensibili"))
                }.frame(maxWidth: .infinity)
            }.disabled(scanning)
            Text(L("Email, telefoni, numeri lunghi e possibili chiavi. Le aree arancioni sono suggerimenti da confermare."))
                .font(.caption).foregroundStyle(.secondary)
            if let scanMessage { Text(L(scanMessage)).font(.caption).foregroundStyle(.secondary) }
            if !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            Toggle("\(index + 1). \(L(suggestion.kind.rawValue))", isOn: Binding(
                                get: { selectedSuggestions.contains(suggestion.id) },
                                set: { if $0 { selectedSuggestions.insert(suggestion.id) } else { selectedSuggestions.remove(suggestion.id) } }
                            )).toggleStyle(.checkbox).font(.caption)
                        }
                    }
                }.frame(maxHeight: 130)
                Button(LF("Aggiungi selezionate (%d)", selectedSuggestions.count)) {
                    let selected = suggestions.filter { selectedSuggestions.contains($0.id) }
                    masks.append(contentsOf: selected.map(\.mask))
                    suggestions.removeAll { selectedSuggestions.contains($0.id) }
                    selectedSuggestions.removeAll()
                    scanMessage = L("Suggerimenti aggiunti alle maschere. Verifica le aree coperte.")
                }.disabled(selectedSuggestions.isEmpty)
            }
            Spacer(minLength: 0)
        }
    }

    private var pendingMask: PrivacyMask? {
        guard let start = dragStart, let end = dragEnd else { return nil }
        return PrivacyMask(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                        width: abs(end.x - start.x), height: abs(end.y - start.y)))
    }

    private func normalized(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / max(1, width))), y: min(1, max(0, point.y / max(1, height))))
    }

    private func detect() {
        scanTask?.cancel()
        scanning = true
        scanMessage = nil
        scanTask = Task { @MainActor in
            do {
                let found = try await PrivacyScanner.scan(image)
                guard !Task.isCancelled else { return }
                suggestions = found
                selectedSuggestions = Set(found.map(\.id))
                scanMessage = found.isEmpty ? L("Nessun suggerimento. Puoi comunque disegnare maschere manuali.") : L("Verifica le aree arancioni prima di aggiungerle.")
            } catch {
                guard !Task.isCancelled else { return }
                scanMessage = L("Analisi non riuscita. Puoi disegnare le maschere manualmente.")
            }
            scanning = false
        }
    }
}
