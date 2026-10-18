import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreMediaIO

struct DeviceDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isPhone: Bool
}

enum RecordingCodec: String, CaseIterable, Identifiable, Sendable {
    case h264 = "H.264"
    case hevc = "HEVC"
    var id: String { rawValue }
    fileprivate var avCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
}

enum RecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard = "Standard"
    case high = "Alta"
    case maximum = "Massima"
    var id: String { rawValue }
    fileprivate var bitsPerPixel: Double {
        switch self { case .standard: return 0.10; case .high: return 0.18; case .maximum: return 0.30 }
    }
}

/// Each window owns an engine; discovery alone never requests camera or microphone access.
@MainActor
final class CaptureEngine: ObservableObject {
    @Published private(set) var devices: [DeviceDescriptor] = []
    @Published private(set) var status = "Collega iPhone o iPad via USB e autorizza il Mac sul dispositivo."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var hasAudio = false
    @Published private(set) var recordingURL: URL?
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var isDiscovering = false

    let session: AVCaptureSession
    private nonisolated let worker: CaptureWorker
    private var startGeneration = 0

    init() {
        let worker = CaptureWorker()
        self.worker = worker
        self.session = worker.session
        worker.onState = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = state.status
                self.errorMessage = state.error
                self.isRunning = state.running
                self.isFinalizing = state.finalizing
                self.isRecording = state.recording
                self.hasAudio = state.hasAudio
                self.recordingURL = state.recordingURL
                self.frameSize = state.frameSize
                self.framesPerSecond = state.fps
            }
        }
        worker.onPreview = { [weak self] image in
            Task { @MainActor [weak self] in self?.previewImage = image }
        }
        refreshDevices()
    }

    deinit { worker.shutdown() }

    func refreshDevices() {
        CaptureWorker.enableDeviceScreenCapture()
        devices = CaptureWorker.discoverDevices().map {
            let description = ($0.localizedName + " " + $0.modelID).lowercased()
            return DeviceDescriptor(id: $0.uniqueID, name: $0.localizedName,
                                    isPhone: description.contains("iphone") || description.contains("ipad") || description.contains("ios"))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Camera authorization can gate iOS screen discovery itself on newer macOS.
    /// Only an explicit user action calls this; initialization never prompts.
    func authorizeAndRefreshDevices() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        errorMessage = nil
        status = "Consenti l’accesso Fotocamera per rilevare lo schermo iPhone/iPad…"
        guard await Self.authorization(for:.video) else {
            errorMessage = "Accesso Fotocamera necessario per rilevare lo schermo iOS. Abilita Specchio Studio in Impostazioni di Sistema → Privacy e sicurezza → Fotocamera."
            status = "Rilevamento USB non autorizzato"
            return
        }
        for _ in 0..<20 {
            refreshDevices()
            if !devices.isEmpty { break }
            try? await Task.sleep(for:.milliseconds(250))
            if Task.isCancelled { return }
        }
        if !isRunning {
            status = devices.isEmpty
                ? "Nessuno schermo iOS rilevato. Sblocca il dispositivo e verifica l’autorizzazione nel Finder."
                : "Dispositivo rilevato. Selezionalo e premi Connetti."
        }
    }

    func start(deviceID: String) async {
        startGeneration += 1
        let generation = startGeneration
        errorMessage = nil
        status = "Autorizzazione e connessione…"
        let videoAllowed = await Self.authorization(for: .video)
        guard generation == startGeneration else { return }
        guard videoAllowed else {
            errorMessage = "Accesso alla fotocamera negato. Abilitalo in Impostazioni di Sistema → Privacy e sicurezza → Fotocamera."
            status = "Autorizzazione necessaria"
            return
        }
        guard let device = CaptureWorker.discoverDevices().first(where: { $0.uniqueID == deviceID }) else {
            errorMessage = "Dispositivo non disponibile. Verifica il cavo USB, sbloccalo e autorizza questo Mac."
            status = "Dispositivo non trovato"
            refreshDevices()
            return
        }
        let supportsAudio = device.hasMediaType(.audio) || device.hasMediaType(.muxed)
        let audioAllowed = supportsAudio ? await Self.authorization(for: .audio) : false
        guard generation == startGeneration else { return }
        await worker.start(device: device, includeAudio: audioAllowed)
    }

    func beginExternalSource(name: String, includesAudio: Bool = false) async -> Bool {
        startGeneration += 1
        return await worker.beginExternalSource(name: name, includesAudio: includesAudio)
    }

    nonisolated func ingestExternalSampleBuffer(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        worker.ingestExternalSampleBuffer(sampleBuffer, isVideo: isVideo)
    }

    func endExternalSource() { stop() }

    func stop() {
        startGeneration += 1
        worker.stop()
    }

    func startRecording(to url: URL, codec: RecordingCodec = .h264, quality: RecordingQuality = .high) {
        worker.startRecording(to: url, codec: codec, quality: quality)
    }

    func stopRecording() async { await worker.stopRecording() }

    func snapshot() -> NSImage? { worker.snapshot() }

    private static func authorization(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        default: return false
        }
    }

    /// Hardware-independent check of the exact snapshot and writer path used in live capture.
    static func runSelfTest(in directory: URL) async throws -> URL {
        try await CaptureWorker.runSelfTest(in: directory, codec: .h264)
    }

    static func selfTest(directory: URL) async throws -> String {
        let h264 = try await CaptureWorker.runSelfTest(in: directory, codec: .h264)
        let hevc = try await CaptureWorker.runSelfTest(in: directory, codec: .hevc)
        return "PASS: snapshot, H.264 and HEVC. Files: \(h264.lastPathComponent), \(hevc.lastPathComponent)"
    }
}

private final class SampleBox: @unchecked Sendable {
    let sample: CMSampleBuffer
    init(_ sample: CMSampleBuffer) { self.sample = sample }
}

private struct CaptureState {
    var status = "Pronto"
    var error: String?
    var running = false
    var recording = false
    var finalizing = false
    var hasAudio = false
    var recordingURL: URL?
    var frameSize: CGSize = .zero
    var fps: Double = 0
}

private enum CaptureFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Session configuration, delegates and asset writer all share a single serial queue.
private final class CaptureWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onState: ((CaptureState) -> Void)?
    var onPreview: ((NSImage?) -> Void)?
    private let queue = DispatchQueue(label: "studio.specchio.capture", qos: .userInitiated)
    private let frameLock = NSLock()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var latestPixelBuffer: CVPixelBuffer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var state = CaptureState()
    private var selectedDeviceID: String?
    private var externalSource = false
    private var externalAudio = false
    private var lastPreviewDate: CFAbsoluteTime = 0
    private var observers: [NSObjectProtocol] = []
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var writerOrigin: CMTime?
    private var recordingDestination: URL?
    private var recordingSize: CGSize = .zero
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastFPSDate = CFAbsoluteTimeGetCurrent()
    private var frameCount = 0

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            self?.queue.async { [weak self] in
                guard let self, device.uniqueID == self.selectedDeviceID else { return }
                self.stopOnQueue(message: "Dispositivo scollegato. Ricollegalo e premi Avvia.")
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] notification in
            let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Errore della sessione video."
            self?.queue.async { [weak self] in self?.stopOnQueue(message: detail) }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    static func enableDeviceScreenCapture() {
        var address = CMIOObjectPropertyAddress(mSelector: UInt32(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                                               mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: UInt32(kCMIOObjectPropertyElementMain))
        var enabled: UInt32 = 1
        _ = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
                                     UInt32(MemoryLayout.size(ofValue: enabled)), &enabled)
    }

    private static var screenDiscovery: AVCaptureDevice.DiscoverySession?

    static func discoverDevices() -> [AVCaptureDevice] {
        enableDeviceScreenCapture()
        // Keep discovery alive while the iOS provider publishes devices. On recent
        // macOS, screen providers can also be in the Continuity Camera category.
        if screenDiscovery == nil {
            screenDiscovery = AVCaptureDevice.DiscoverySession(deviceTypes:[.external,.continuityCamera],mediaType:nil,position:.unspecified)
        }
        let found = screenDiscovery?.devices ?? []
        var seen = Set<String>()
        return found.filter {
            let isIOSScreen = $0.hasMediaType(.muxed) || $0.modelID == "iOS Device"
            return seen.insert($0.uniqueID).inserted && $0.isConnected && (isIOSScreen || !$0.isContinuityCamera)
        }
    }

    func start(device: AVCaptureDevice, includeAudio: Bool) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !state.finalizing && writer == nil else {
                    state.error = "Ferma la registrazione prima di cambiare dispositivo."
                    publish()
                    continuation.resume()
                    return
                }
                if session.isRunning { session.stopRunning() }
                externalSource = false
                externalAudio = false
                state.hasAudio = false
                clearFrame()
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw CaptureFailure.message("Questo dispositivo non può essere acquisito. Potrebbe essere già usato da un'altra app.") }
                    session.addInput(input)
                    if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(self, queue: queue)
                    guard session.canAddOutput(videoOutput) else { throw CaptureFailure.message("Uscita video non disponibile.") }
                    session.addOutput(videoOutput)
                    if includeAudio && input.ports.contains(where: { $0.mediaType == .audio }) && session.canAddOutput(audioOutput) {
                        audioOutput.setSampleBufferDelegate(self, queue: queue)
                        session.addOutput(audioOutput)
                    }
                    session.commitConfiguration()
                    selectedDeviceID = device.uniqueID
                    frameCount = 0
                    lastFPSDate = CFAbsoluteTimeGetCurrent()
                    session.startRunning()
                    state.running = session.isRunning
                    state.hasAudio = state.running && session.outputs.contains(audioOutput)
                    state.error = nil
                    state.frameSize = .zero
                    state.fps = 0
                    state.status = state.running ? "In diretta · \(device.localizedName)" : "Avvio video non riuscito"
                    if !state.running { state.error = "Il dispositivo non ha avviato il flusso video." }
                    publish()
                } catch {
                    session.commitConfiguration()
                    state.running = false
                    state.hasAudio = false
                    state.error = error.localizedDescription
                    state.status = "Connessione non riuscita"
                    publish()
                }
                continuation.resume()
            }
        }
    }

    func beginExternalSource(name: String, includesAudio: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard writer == nil, !state.finalizing else {
                    state.error = "Ferma la registrazione prima di cambiare sorgente."
                    publish(); continuation.resume(returning: false); return
                }
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                session.commitConfiguration()
                selectedDeviceID = nil
                externalSource = true
                externalAudio = includesAudio
                state.hasAudio = includesAudio
                clearFrame()
                state.running = true
                state.error = nil
                state.status = "In diretta · \(name)"
                frameCount = 0
                lastFPSDate = CFAbsoluteTimeGetCurrent()
                publish()
                continuation.resume(returning: true)
            }
        }
    }

    func ingestExternalSampleBuffer(_ sample: CMSampleBuffer, isVideo: Bool) {
        let box = SampleBox(sample)
        queue.async { [self] in
            guard externalSource, state.running else { return }
            consume(box.sample, isVideo: isVideo)
        }
    }

    func stop() { queue.async { [self] in stopOnQueue(message: nil) } }
    func shutdown() { queue.async { [self] in stopOnQueue(message: nil); onState = nil; onPreview = nil } }

    private func stopOnQueue(message: String?) {
        if session.isRunning { session.stopRunning() }
        selectedDeviceID = nil
        externalSource = false
        externalAudio = false
        state.hasAudio = false
        clearFrame()
        state.running = false
        state.fps = 0
        state.status = message == nil ? "Acquisizione interrotta" : "Connessione interrotta"
        state.error = message
        finishRecordingOnQueue()
        publish()
    }

    func startRecording(to url: URL, codec: RecordingCodec, quality: RecordingQuality) {
        queue.async { [self] in
            guard state.running, state.frameSize.width > 0 else {
                state.error = "Attendi il primo fotogramma prima di registrare."
                publish(); return
            }
            guard writer == nil, !state.finalizing else { return }
            do {
                try prepareWriter(to: url, codec: codec, quality: quality,
                                  audioSettings: externalSource
                                    ? (externalAudio ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000] : nil)
                                    : (session.outputs.contains(audioOutput) ? audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) : nil))
                state.error = nil
                state.recording = true
                state.recordingURL = nil
                publish()
            } catch {
                state.error = "Registrazione non avviata: \(error.localizedDescription)"
                publish()
            }
        }
    }

    private func prepareWriter(to url: URL, codec: RecordingCodec, quality: RecordingQuality, audioSettings: [String: Any]?) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CaptureFailure.message("Il file di destinazione esiste già. Scegli un nuovo nome.") }
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = Int(state.frameSize.width), height = Int(state.frameSize.height)
        let bitRate = max(2_000_000, Int(Double(width * height) * max(30, state.fps) * quality.bitsPerPixel))
        let settings: [String: Any] = [AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: width, AVVideoHeightKey: height,
                                      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate,
                                                                       AVVideoMaxKeyFrameIntervalKey: 60]]
        guard assetWriter.canApply(outputSettings: settings, forMediaType: .video) else { throw CaptureFailure.message("Codec non supportato per questa risoluzione. Prova H.264.") }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(video) else { throw CaptureFailure.message("Impossibile creare la traccia video.") }
        assetWriter.add(video)
        var audio: AVAssetWriterInput?
        if let settings = audioSettings, assetWriter.canApply(outputSettings: settings, forMediaType: .audio) {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) { assetWriter.add(input); audio = input }
        }
        writer = assetWriter
        videoInput = video
        audioInput = audio
        recordingDestination = url
        recordingSize = state.frameSize
        writerOrigin = nil
    }

    func stopRecording() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                finishWaiters.append(continuation)
                finishRecordingOnQueue()
            }
        }
    }

    private func finishRecordingOnQueue() {
        guard !state.finalizing else { return }
        guard let assetWriter = writer else { resumeFinishWaiters(); return }
        state.finalizing = true
        state.recording = false
        publish()
        if assetWriter.status == .writing {
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            // Retain the worker until finalization, including when its window closes.
            assetWriter.finishWriting { [self] in
                queue.async { [self] in
                    guard let writer else { return }
                    completeRecording(writer)
                }
            }
        } else {
            if assetWriter.status == .unknown { assetWriter.cancelWriting() }
            completeRecording(assetWriter)
        }
    }

    private func completeRecording(_ assetWriter: AVAssetWriter) {
        if assetWriter.status == .completed {
            state.recordingURL = recordingDestination
        } else {
            state.error = assetWriter.error?.localizedDescription ?? "Nessun fotogramma registrato. Il file vuoto è stato eliminato."
            if let destination = recordingDestination { try? FileManager.default.removeItem(at: destination) }
        }
        writer = nil; videoInput = nil; audioInput = nil; writerOrigin = nil; recordingDestination = nil; recordingSize = .zero
        state.finalizing = false
        publish()
        resumeFinishWaiters()
    }

    private func resumeFinishWaiters() {
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard state.running, !externalSource else { return }
        consume(sampleBuffer, isVideo: output === videoOutput)
    }

    private func consume(_ sample: CMSampleBuffer, isVideo: Bool) {
        guard CMSampleBufferDataIsReady(sample) else { return }
        if isVideo, let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
            frameLock.lock(); latestPixelBuffer = pixelBuffer; frameLock.unlock()
            let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            let changedSize = state.frameSize != size
            if writer != nil, !state.finalizing, recordingSize != .zero, recordingSize != size {
                state.error = "Risoluzione cambiata: registrazione salvata. Avviane una nuova per la nuova risoluzione."
                finishRecordingOnQueue()
            }
            state.frameSize = size
            frameCount += 1
            let now = CFAbsoluteTimeGetCurrent(), interval = now - lastFPSDate
            if now - lastPreviewDate >= 1.0 / 30 {
                lastPreviewDate = now
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                let scale = min(1, 1600 / max(image.extent.width, image.extent.height))
                let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let cg = imageContext.createCGImage(scaled, from: scaled.extent) ?? bitmapImage(from: pixelBuffer) {
                    onPreview?(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                }
            }
            if interval >= 1 {
                state.fps = Double(frameCount) / interval
                frameCount = 0; lastFPSDate = now
                publish()
            } else if changedSize { publish() }
        }
        guard let assetWriter = writer, !state.finalizing else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        guard timestamp.isValid && timestamp.isNumeric else { return }
        if writerOrigin == nil {
            guard isVideo else { return }
            guard assetWriter.startWriting() else {
                state.error = assetWriter.error?.localizedDescription ?? "Impossibile avviare il file video."
                finishRecordingOnQueue(); return
            }
            assetWriter.startSession(atSourceTime: timestamp)
            writerOrigin = timestamp
        }
        guard let origin = writerOrigin, timestamp >= origin, assetWriter.status == .writing else { return }
        let input = isVideo ? videoInput : audioInput
        if let input, input.isReadyForMoreMediaData, !input.append(sample) {
            state.error = assetWriter.error?.localizedDescription ?? "Scrittura del video non riuscita."
            finishRecordingOnQueue()
        }
    }

    func snapshot() -> NSImage? {
        frameLock.lock(); let pixelBuffer = latestPixelBuffer; frameLock.unlock()
        guard let pixelBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) ?? bitmapImage(from: pixelBuffer) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// CPU fallback also works when a headless test process has no Metal/IOSurface access.
    private func bitmapImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let data = Data(bytes: bytes, count: rowBytes * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: CVPixelBufferGetWidth(pixelBuffer), height: height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func clearFrame() {
        frameLock.lock(); latestPixelBuffer = nil; frameLock.unlock()
        state.frameSize = .zero
        state.fps = 0
        lastPreviewDate = 0
        onPreview?(nil)
    }

    private func publish() { onState?(state) }

    static func runSelfTest(in directory: URL, codec: RecordingCodec) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let worker = CaptureWorker()
        let destination = directory.appendingPathComponent("capture-self-test-\(codec.rawValue)-\(UUID().uuidString).mov")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.queue.async {
                do {
                    worker.state.frameSize = CGSize(width: 640, height: 480)
                    worker.state.fps = 30
                    try worker.prepareWriter(to: destination, codec: codec, quality: .standard, audioSettings: nil)
                    // Synthetic BGRA frames exercise CI snapshots and real H.264 encoding.
                    for index in 0..<30 {
                        var buffer: CVPixelBuffer?
                        guard CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA,
                                                  [kCVPixelBufferCGImageCompatibilityKey: true,
                                                   kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer) == kCVReturnSuccess,
                              let buffer else { throw CaptureFailure.message("Creazione frame di prova fallita.") }
                        CVPixelBufferLockBaseAddress(buffer, [])
                        if let address = CVPixelBufferGetBaseAddress(buffer) {
                            memset(address, Int32(index * 7), CVPixelBufferGetDataSize(buffer))
                        }
                        CVPixelBufferUnlockBaseAddress(buffer, [])
                        var description: CMVideoFormatDescription?
                        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description)
                        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: Int64(index), timescale: 30), decodeTimeStamp: .invalid)
                        var sample: CMSampleBuffer?
                        guard let description, CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: description,
                                                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
                              let sample else { throw CaptureFailure.message("Creazione sample di prova fallita.") }
                        worker.consume(sample, isVideo: true)
                    }
                    guard worker.snapshot() != nil else { throw CaptureFailure.message("Snapshot di prova fallito.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        await worker.stopRecording()
        let asset = AVURLAsset(url: destination)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard duration.seconds > 0, !tracks.isEmpty else { throw CaptureFailure.message("Il video di prova non contiene fotogrammi.") }
        return destination
    }
}
