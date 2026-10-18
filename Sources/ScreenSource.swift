import AppKit
@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import Combine

/// Captures an explicitly selected Mac window/display. WirelessSource handles iOS AirPlay.
@MainActor
final class ScreenSource: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isChoosing = false
    @Published private(set) var status = L("Scegli una finestra, Simulator o uno schermo.")
    @Published private(set) var errorMessage: String?

    // The system picker is a process-wide singleton, even with multiple windows.
    private static weak var selectionOwner: ScreenSource?
    private static var registeredIDs = Set<UUID>()
    private let id = UUID()
    private let observer = ScreenSourceObserver()
    private let sampleQueue = DispatchQueue(label: "studio.specchio.screen", qos: .userInitiated)
    private var stream: SCStream?
    private var output: ScreenSampleForwarder?
    private var engine: CaptureEngine?
    private var includesAudio = false
    private var registered = false
    private var externalClaimed = false
    private var generation = 0

    init() { observer.owner = self }

    deinit {
        let retainedObserver = observer
        let retainedStream = stream
        let retainedEngine = externalClaimed ? engine : nil
        let retainedID = id
        output?.deactivate()
        Task { @MainActor in
            let picker = SCContentSharingPicker.shared
            picker.remove(retainedObserver)
            Self.registeredIDs.remove(retainedID)
            if Self.registeredIDs.isEmpty { picker.isActive = false }
            if let retainedStream { try? await retainedStream.stopCapture() }
            retainedEngine?.endExternalSource()
        }
    }

    /// Call only from a user action. The system chooser grants capture access to
    /// the selection; no camera or microphone permission is needed here.
    func start(engine: CaptureEngine, includesAudio: Bool = false) {
        guard !isChoosing else { return }
        guard Self.selectionOwner == nil || Self.selectionOwner === self else {
            errorMessage = L("Completa la selezione nell'altra finestra prima di aprirne una nuova.")
            return
        }
        guard !engine.isRecording, !engine.isFinalizing else {
            errorMessage = L("Ferma la registrazione prima di cambiare sorgente.")
            return
        }
        errorMessage = nil
        self.engine = engine
        self.includesAudio = includesAudio
        let picker = SCContentSharingPicker.shared
        if !registered {
            picker.add(observer)
            Self.registeredIDs.insert(id)
            registered = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        configuration.allowsChangingSelectedContent = true
        picker.defaultConfiguration = configuration
        Self.selectionOwner = self
        isChoosing = true
        status = L("Seleziona la sorgente nel selettore di macOS…")
        picker.isActive = true
        if let stream {
            picker.setConfiguration(configuration, for: stream)
            picker.present(for: stream)
        } else {
            picker.present()
        }
    }

    func stop() async {
        generation += 1
        let oldStream = stream
        let oldEngine = externalClaimed ? engine : nil
        externalClaimed = false
        output?.deactivate()
        output = nil
        stream = nil
        engine = nil
        isActive = false
        isChoosing = false
        unregister()
        oldEngine?.endExternalSource()
        if let oldStream { try? await oldStream.stopCapture() }
        status = L("Acquisizione schermo interrotta")
    }

    fileprivate func cancelled(for candidate: SCStream?) {
        guard accepts(candidate) else { return }
        isChoosing = false
        if Self.selectionOwner === self { Self.selectionOwner = nil }
        status = isActive ? L("In diretta · Finestra o schermo") : L("Selezione annullata")
        if !isActive { engine = nil; unregister() }
    }

    fileprivate func pickerFailed(_ error: Error) {
        guard Self.selectionOwner === self else { return }
        cancelled(for: stream)
        errorMessage = LF("Impossibile aprire il selettore macOS: %@", error.localizedDescription)
    }

    fileprivate func selected(_ filter: SCContentFilter, for candidate: SCStream?) async {
        guard accepts(candidate), let engine else { return }
        isChoosing = false
        if Self.selectionOwner === self { Self.selectionOwner = nil }
        guard !engine.isRecording, !engine.isFinalizing else {
            errorMessage = L("Ferma la registrazione prima di cambiare sorgente.")
            return
        }
        generation += 1
        let token = generation
        let configuration = Self.configuration(filter: filter, includesAudio: includesAudio)
        do {
            externalClaimed = true
            let accepted = await engine.beginExternalSource(name: L("Finestra o schermo"), includesAudio: includesAudio)
            guard token == generation else { return }
            guard accepted else {
                externalClaimed = isActive
                errorMessage = L("Sorgente occupata: ferma la registrazione e riprova.")
                if !isActive { self.engine = nil; unregister() }
                return
            }
            if let stream {
                // Keep dimensions fixed for the duration of every recording.
                try await stream.updateContentFilter(filter)
                guard token == generation else { return }
                try await stream.updateConfiguration(configuration)
                guard token == generation else { return }
            } else {
                status = L("Avvio acquisizione schermo…")
                let forwarder = ScreenSampleForwarder(engine: engine)
                let newStream = SCStream(filter: filter, configuration: configuration, delegate: observer)
                output = forwarder
                stream = newStream
                try newStream.addStreamOutput(forwarder, type: .screen, sampleHandlerQueue: sampleQueue)
                // Keep the output attached so a later picker update can enable
                // audio. No audio samples are captured while capturesAudio=false.
                try newStream.addStreamOutput(forwarder, type: .audio, sampleHandlerQueue: sampleQueue)
                try await newStream.startCapture()
                guard token == generation else { return }
            }
            isActive = true
            errorMessage = nil
            status = includesAudio ? L("In diretta · Finestra o schermo con audio") : L("In diretta · Finestra o schermo")
        } catch {
            guard token == generation else { return }
            await stop()
            status = L("Acquisizione schermo non riuscita")
            errorMessage = LF("%@ Riapri il selettore; verifica anche Privacy e sicurezza → Registrazione schermo.", error.localizedDescription)
        }
    }

    fileprivate func stopped(_ candidate: SCStream, error: Error) async {
        guard candidate === stream else { return }
        await stop()
        status = L("Condivisione terminata")
        errorMessage = error.localizedDescription
    }

    private func accepts(_ candidate: SCStream?) -> Bool {
        if let candidate { return candidate === stream }
        return Self.selectionOwner === self
    }

    private func unregister() {
        if Self.selectionOwner === self { Self.selectionOwner = nil }
        guard registered else { return }
        let picker = SCContentSharingPicker.shared
        picker.remove(observer)
        Self.registeredIDs.remove(id)
        registered = false
        if Self.registeredIDs.isEmpty { picker.isActive = false }
    }

    private static func configuration(filter: SCContentFilter, includesAudio: Bool) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        // Even pixel dimensions are compatible with both H.264 and HEVC writers.
        configuration.width = max(2, Int((filter.contentRect.width * scale).rounded(.up)) / 2 * 2)
        configuration.height = max(2, Int((filter.contentRect.height * scale).rounded(.up)) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 4
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.capturesAudio = includesAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.ignoreShadowsSingleWindow = true
        configuration.streamName = "Specchio Studio"
        return configuration
    }
}

private final class ScreenSourceObserver: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    @MainActor weak var owner: ScreenSource?

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in self?.owner?.cancelled(for: stream) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in await self?.owner?.selected(filter, for: stream) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in self?.owner?.pickerFailed(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in await self?.owner?.stopped(stream, error: error) }
    }
}

/// Samples never cross the main actor; the capture engine serializes its writer.
private final class ScreenSampleForwarder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let engine: CaptureEngine
    private let lock = NSLock()
    private var active = true

    init(engine: CaptureEngine) { self.engine = engine }
    func deactivate() { lock.lock(); active = false; lock.unlock() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        lock.lock(); let shouldForward = active; lock.unlock()
        guard shouldForward, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let rawStatus = attachments.first?[.status] as? Int,
               SCFrameStatus(rawValue: rawStatus) != .complete { return }
            engine.ingestExternalSampleBuffer(sampleBuffer, isVideo: true)
        case .audio:
            engine.ingestExternalSampleBuffer(sampleBuffer, isVideo: false)
        default: break
        }
    }
}
