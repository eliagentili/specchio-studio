import Foundation
import AVFoundation

private final class WirelessTestContext {
    let engine: CaptureEngine
    init(_ engine: CaptureEngine) { self.engine=engine }
}

enum WirelessIntegrationTests {
    @MainActor static func run(directory: URL) async throws {
        let engine=CaptureEngine()
        guard await engine.beginExternalSource(name:"Wireless fixture",includesAudio:false) else { fatalError("Wireless source rejected") }
        let context=WirelessTestContext(engine)
        let receiver=SSWirelessCreate(Unmanaged.passUnretained(context).toOpaque(), { ctx,sample,video in
            guard let ctx,let sample else { return }
            Unmanaged<WirelessTestContext>.fromOpaque(ctx).takeUnretainedValue().engine.ingestExternalSampleBuffer(sample,isVideo:video)
        }, { ctx,event,_ in
            guard event==3,let ctx else { return }
            let engine=Unmanaged<WirelessTestContext>.fromOpaque(ctx).takeUnretainedValue().engine
            Task { @MainActor in engine.endExternalSource() }
        })!
        defer { SSWirelessDestroy(receiver); withExtendedLifetime(context) {} }
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/wireless.h264")
        let bytes=try Data(contentsOf:fixture)
        func feed() {
            bytes.withUnsafeBytes { raw in
                SSWirelessFeedVideo(receiver,raw.bindMemory(to:UInt8.self).baseAddress,Int32(bytes.count),false)
            }
        }
        feed(); try await Task.sleep(for:.milliseconds(150))
        guard engine.previewImage != nil,engine.snapshot() != nil,engine.frameSize==CGSize(width:360,height:640) else { fatalError("Wireless frame did not reach the preview/snapshot engine") }
        let destination=directory.appendingPathComponent("wireless-pipeline.mov")
        try? FileManager.default.removeItem(at:destination)
        engine.startRecording(to:destination,codec:.h264,quality:.standard)
        for _ in 0..<12 { feed(); try await Task.sleep(for:.milliseconds(34)) }
        SSWirelessFeedEnd(receiver)
        for _ in 0..<30 {
            try await Task.sleep(for:.milliseconds(100))
            if !engine.isRunning && !engine.isRecording && !engine.isFinalizing { break }
        }
        guard !engine.isRunning,!engine.isRecording,!engine.isFinalizing else { fatalError("Wireless EOF did not finalize the recording automatically") }
        guard engine.errorMessage==nil else { fatalError("Wireless writer failed: \(engine.errorMessage ?? "")") }
        let asset=AVURLAsset(url:destination)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let duration=try await asset.load(.duration).seconds
        guard tracks.count==1,duration>0.25 else { fatalError("Wireless recording incomplete") }
        engine.endExternalSource()
        print("PASS: AirPlay decoder → preview/snapshot → H.264 recording finalized on peer EOF, 360×640, \(String(format:"%.3f",duration)) s")
    }
}
