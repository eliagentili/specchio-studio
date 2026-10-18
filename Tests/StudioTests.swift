import SwiftUI
import AppKit
import Vision

@main struct StudioTests {
    @MainActor static func main() async throws {
        let destination = URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        _ = NSApplication.shared
        try await StudioStyleTests.run()
        try await PrivacyTests.run(directory:destination)
        try await BugReportTests.run(directory:destination)
        var gate = WirelessSampleGate()
        guard let first = gate.firstFrame(), gate.firstFrame() == nil else { fatalError("Wireless first frame must be claimed once") }
        gate.disconnect()
        guard !gate.enable(for:first), !gate.samplesEnabled else { fatalError("Disconnected wireless peer enabled stale samples") }
        guard let reconnect = gate.firstFrame(), reconnect != first else { fatalError("Wireless reconnect was not rearmed") }
        gate.retry(for:reconnect)
        guard gate.firstFrame() == reconnect, gate.enable(for:reconnect), gate.samplesEnabled else { fatalError("Busy wireless engine could not retry the first frame") }
        gate.disconnect()
        guard !gate.samplesEnabled, !gate.enable(for:reconnect) else { fatalError("Wireless stop did not invalidate samples") }
        print("PASS: wireless first-frame cancellation, reconnect and busy-engine retry")
        try await WirelessIntegrationTests.run(directory:destination)
        print(try await CaptureEngine.selfTest(directory:destination))
        for format in CompositionFormat.allCases {
            for bounds in [CGSize(width:900,height:500), CGSize(width:500,height:900)] {
                let fitted = format.fittedSize(in:bounds)
                guard fitted.width > 0, fitted.height > 0, fitted.width <= bounds.width + 0.001,
                      fitted.height <= bounds.height + 0.001 else { fatalError("Composition preset escaped preview bounds") }
                if let size = format.exportSize {
                    guard abs(fitted.width / fitted.height - size.width / size.height) < 0.001 else { fatalError("Composition preset aspect ratio changed") }
                } else if fitted != bounds { fatalError("Adaptive composition did not fill preview") }
            }
            if let size = format.exportSize {
                let view = StudioCanvas(image:nil,demo:true,backdrop:.aurora,frame:true,rotation:0,flipped:false,zoom:1.2,grid:false,marks:[],annotationMode:false,onPoint:nil,format:format)
                    .frame(width:size.width,height:size.height).preferredColorScheme(.dark)
                let renderer = ImageRenderer(content:view); renderer.scale = 0.25
                guard let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff),
                      bitmap.pixelsWide == Int(size.width / 4), bitmap.pixelsHigh == Int(size.height / 4),
                      let data = bitmap.representation(using:.png,properties:[:]) else { fatalError("Composition preset PNG dimensions changed") }
                try data.write(to:destination.appendingPathComponent("preset-\(format.id).png"))
            }
        }
        print("PASS: portrait, square and landscape preview ratios and PNG dimensions")
        for (name,bg,rotation) in [("demo",Backdrop.aurora,0),("transparent",Backdrop.transparent,1)] {
            let view = StudioCanvas(image:nil,demo:true,backdrop:bg,frame:true,rotation:rotation,flipped:false,zoom:1,grid:false,marks:[],annotationMode:false,onPoint:nil).frame(width:1000,height:1200).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content:view); renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let data = bitmap.representation(using:.png,properties:[:]) else { fatalError("Composition rendering failed") }
            guard bitmap.pixelsWide == 1000, bitmap.pixelsHigh == 1200 else { fatalError("Incorrect export dimensions") }
            if bg == .transparent { guard (bitmap.colorAt(x:0,y:0)?.alphaComponent ?? 1) < 0.1 else { fatalError("PNG alpha not preserved") } }
            try data.write(to:destination.appendingPathComponent("\(name).png"))
            if bg == .aurora {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                try VNImageRequestHandler(data:data).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:" ")
                guard text.contains("MAKE"), text.contains("ROOM") else { fatalError("Rendered demo text missing or clipped: \(text)") }
                print("PASS: composition PNG, readable demo title and OCR")
            }
        }
        print("PASS: rotation and transparent export")
        if CommandLine.arguments.count > 2 {
            print(try await VideoExporter.selfTest(source:URL(fileURLWithPath:CommandLine.arguments[2]),directory:destination))
            try await CreatorExportTests.run(source:URL(fileURLWithPath:CommandLine.arguments[2]),directory:destination)
        }
    }
}
