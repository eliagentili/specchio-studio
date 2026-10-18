import AppKit

enum StudioStyleTests {
    @MainActor static func run() async throws {
        let suite = "it.local.specchio.style-tests.\(UUID().uuidString)"
        guard VideoTrimTime.parse("0.1") == 0.1, VideoTrimTime.parse("0,4") == 0.4,
              VideoTrimTime.parse(" 0 ") == 0, VideoTrimTime.parse("") == nil,
              VideoTrimTime.parse("-1") == nil, VideoTrimTime.parse("nan") == nil,
              VideoTrimTime.parse("1,2.3") == nil else { fatalError("Trim time parser accepted invalid input or lost decimals") }
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let value = StudioStyle(name:"Demo",backdrop:Backdrop.ocean.rawValue,showFrame:true,rotation:3,
            flipped:true,zoom:1.25,format:CompositionFormat.square.rawValue,exportScale:2)
        try StudioStyleStore.save([value],defaults:defaults)
        guard StudioStyleStore.load(defaults:defaults) == [value] else { fatalError("Style did not round-trip") }
        var invalid = value; invalid.name = ""; invalid.zoom = 20
        try StudioStyleStore.save([invalid,value],defaults:defaults)
        guard StudioStyleStore.load(defaults:defaults) == [value] else { fatalError("Invalid style restored") }
        let encoded = String(data:try JSONEncoder().encode(value),encoding:.utf8)!
        guard !encoded.contains("mask"), !encoded.contains("image"), !encoded.contains("source") else {
            fatalError("Style contains source content")
        }
        let model = StudioModel()
        model.savedStyles = [value]; model.selectedStyleID = value.id
        let mask = PrivacyMask(rect:CGRect(x:0.1,y:0.1,width:0.2,height:0.3))
        model.privacyMasks = [mask]
        model.applySelectedStyle()
        guard model.backdrop == .ocean, model.rotation == 3, model.flipped, model.zoom == 1.25,
              model.compositionFormat == .square, model.exportScale == 2,
              model.privacyMasks == [mask] else { fatalError("Style application altered content or lost appearance") }
        let original = Mark(points:[CGPoint(x:0.5,y:0.5),CGPoint(x:0.6,y:0.4)],color:.orange)
        let portrait = CGSize(width:1080,height:1920), landscape = CGSize(width:1920,height:1080)
        let projected = CanvasAnnotations.reproject([original],from:portrait,to:landscape,sourceAspect:0.5,quarterTurns:0)
        let restored = CanvasAnnotations.reproject(projected,from:landscape,to:portrait,sourceAspect:0.5,quarterTurns:0)
        guard projected[0].points[0] == CGPoint(x:0.5,y:0.5),
              abs(projected[0].points[1].x - 0.6) > 0.02,
              abs(restored[0].points[1].x - original.points[1].x) < 0.0001,
              abs(restored[0].points[1].y - original.points[1].y) < 0.0001 else {
            fatalError("Annotations detached from the source across aspect ratios")
        }
        let pasteboard = NSPasteboard(name:NSPasteboard.Name("Specchio-OCR-Test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("clipboard sentinel",forType:.string)
        model.demo = true
        let staleRequest = model.recognizeText(pasteboard:pasteboard,recognition:{ _ in
            try? await Task.sleep(for:.milliseconds(70))
            return "private@example.com"
        })
        await Task.yield()
        model.privacyMasks = [PrivacyMask(rect:CGRect(x:0,y:0,width:1,height:1))]
        await staleRequest?.value
        guard pasteboard.string(forType:.string) == "clipboard sentinel", !model.ocrBusy else {
            fatalError("Stale OCR exposed text after privacy masks changed")
        }
        let freshRequest = model.recognizeText(pasteboard:pasteboard,recognition:{ _ in "public heading" })
        await freshRequest?.value
        guard pasteboard.string(forType:.string) == "public heading" else { fatalError("Current OCR result was lost") }
        print("PASS: reusable style persistence, validation and source-content isolation")
        print("PASS: in-flight OCR invalidated after privacy changes without touching the system clipboard")
    }
}
