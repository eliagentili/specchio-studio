import AppKit
import Combine
@preconcurrency import AVFoundation

/// Receives AirPlay video directly. No display capture or macOS AirPlay receiver is involved.
@MainActor final class WirelessSource: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = ""
    @Published private(set) var pairingCode = ""
    @Published private(set) var errorMessage: String?
    private static weak var owner: WirelessSource?
    private var worker: WirelessWorker?
    private weak var engine: CaptureEngine?
    private var generation = 0
    private var receiving = false
    private var startingEngine = false
    private var isStopping = false
    let receiverName = "Specchio Studio"

    func start(engine: CaptureEngine) async {
        guard !isStarting, !isListening, !isStopping else { return }
        guard !engine.isRecording, !engine.isFinalizing else {
            errorMessage = L("Ferma la registrazione prima di cambiare sorgente.")
            return
        }
        if let owner = Self.owner, owner !== self {
            errorMessage = L("Il ricevitore wireless è già aperto in un’altra finestra di Specchio.")
            return
        }
        Self.owner = self
        generation += 1
        let token = generation
        isStarting = true; errorMessage = nil; pairingCode = ""
        status = L("Avvio ricevitore wireless…")
        self.engine = engine
        let worker = WirelessWorker(engine: engine)
        self.worker = worker
        worker.onEvent = { [weak self] event, text in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch event {
                case 1: self.pairingCode = text; self.status = L("Inserisci questo codice sull’iPhone o iPad")
                case 2: self.pairingCode = ""; self.status = Self.localizedReceiverMessage(text)
                case 3:
                    self.receiving = false
                    self.engine?.endExternalSource()
                    self.pairingCode = ""; self.status = Self.localizedReceiverMessage(text)
                case 6: self.errorMessage = Self.localizedReceiverMessage(text)
                default: break
                }
            }
        }
        // The receiver is armed before the client connects; a first video frame marks it LIVE.
        worker.onFirstFrame = { [weak self, weak worker] connection in
            Task { @MainActor [weak self, weak worker] in
                guard let self, let worker, self.generation == token, let engine=self.engine else { return }
                guard !self.receiving, !self.startingEngine else {
                    worker.retryFirstFrame(for: connection)
                    return
                }
                self.startingEngine = true
                let ready = await engine.beginExternalSource(name:L("Wireless · iPhone / iPad"),includesAudio:true)
                guard self.generation == token else { return }
                self.startingEngine = false
                if ready {
                    self.receiving = worker.enableSamples(for: connection)
                    if !self.receiving { engine.endExternalSource() }
                } else {
                    worker.retryFirstFrame(for: connection)
                }
            }
        }
        let result = await worker.start(name: receiverName)
        guard generation == token else { await worker.stop(); return }
        isStarting = false
        if result == 0 {
            isListening = true
            if pairingCode.isEmpty { status = L("Su iPhone/iPad: Centro di Controllo → Duplica schermo → Specchio Studio") }
        } else {
            errorMessage = LF("Impossibile avviare il ricevitore wireless (%d). Verifica il permesso Rete locale e riprova.", result)
            status = L("Ricevitore non avviato")
            await stop()
        }
    }

    private static func localizedReceiverMessage(_ text: String) -> String {
        let decoderPrefix = "Video decoding is unavailable ("
        if text.hasPrefix(decoderPrefix), text.hasSuffix(")"),
           let code = Int(text.dropFirst(decoderPrefix.count).dropLast()) {
            return LF("Decodifica video non disponibile (%d)", code)
        }
        return L(text)
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        generation += 1
        let old = worker; worker = nil
        isListening = false; isStarting = false; pairingCode = ""
        // Invalidate a pending first-frame claim before waiting for the native
        // receiver. Its queued begin must be followed by an engine stop too.
        if receiving || startingEngine { engine?.endExternalSource() }
        receiving = false; startingEngine = false
        engine = nil
        await old?.stop()
        if Self.owner === self { Self.owner = nil }
        isStopping = false
    }
}

/// A disconnected peer cannot enable samples after its asynchronous engine claim
/// completes. A busy engine can retry when the next video frame arrives.
struct WirelessSampleGate {
    private(set) var samplesEnabled = false
    private var firstFrameRequested = false
    private var connection = 0

    mutating func firstFrame() -> Int? {
        guard !firstFrameRequested else { return nil }
        firstFrameRequested = true
        return connection
    }

    mutating func enable(for token: Int) -> Bool {
        guard token == connection else { return false }
        samplesEnabled = true
        return true
    }

    mutating func retry(for token: Int) {
        guard token == connection, !samplesEnabled else { return }
        firstFrameRequested = false
    }

    mutating func disconnect() {
        connection += 1
        samplesEnabled = false
        firstFrameRequested = false
    }
}

private final class WirelessWorker: @unchecked Sendable {
    let engine: CaptureEngine
    var onEvent: ((Int,String) -> Void)?
    var onFirstFrame: ((Int) -> Void)?
    private let queue = DispatchQueue(label:"studio.specchio.airplay",qos:.userInitiated)
    private let lock = NSLock()
    private var sampleGate = WirelessSampleGate()
    private var receiver: UnsafeMutableRawPointer?

    init(engine: CaptureEngine) { self.engine = engine }
    deinit { if let receiver { SSWirelessDestroy(receiver) } }

    func enableSamples(for connection: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sampleGate.enable(for: connection)
    }
    func retryFirstFrame(for connection: Int) {
        lock.lock(); defer { lock.unlock() }
        sampleGate.retry(for: connection)
    }
    private func sample(_ sample: CMSampleBuffer, video: Bool) {
        lock.lock()
        let enabled = sampleGate.samplesEnabled
        let first = video ? sampleGate.firstFrame() : nil
        lock.unlock()
        if let first { onFirstFrame?(first) }
        if enabled { engine.ingestExternalSampleBuffer(sample,isVideo:video) }
    }
    private func event(_ code: Int, _ text: String) {
        if code == 3 {
            lock.lock(); sampleGate.disconnect(); lock.unlock()
        }
        onEvent?(code,text)
    }
    func start(name: String) async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    let support = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
                        .appendingPathComponent("Specchio Studio/Wireless",isDirectory:true)
                    try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    let idURL=support.appendingPathComponent("receiver-id.txt")
                    let deviceID: String
                    if let saved=try? String(contentsOf:idURL,encoding:.utf8), saved.count==17 { deviceID=saved }
                    else {
                        var bytes=(0..<6).map { _ in UInt8.random(in:0...255) }; bytes[0]=(bytes[0] & 0xfc) | 0x02
                        deviceID=bytes.map { String(format:"%02X",$0) }.joined(separator:":")
                        try deviceID.write(to:idURL,atomically:true,encoding:.utf8)
                    }
                    receiver=SSWirelessCreate(Unmanaged.passUnretained(self).toOpaque(), { context, sample, video in
                        guard let context, let sample else { return }
                        Unmanaged<WirelessWorker>.fromOpaque(context).takeUnretainedValue().sample(sample,video:video)
                    }, { context, code, message in
                        guard let context, let message else { return }
                        Unmanaged<WirelessWorker>.fromOpaque(context).takeUnretainedValue().event(Int(code),String(cString:message))
                    })
                    guard let receiver else { continuation.resume(returning:-10); return }
                    let result=SSWirelessStart(receiver,name,deviceID,support.appendingPathComponent("pairing.key").path)
                    continuation.resume(returning:Int(result))
                } catch { continuation.resume(returning:-11) }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let receiver { SSWirelessDestroy(receiver); self.receiver=nil }
                lock.lock(); sampleGate.disconnect(); lock.unlock()
                continuation.resume()
            }
        }
    }
}
