import SwiftUI
import AppKit

// Avoid the same-named SDK macro, whose plugin requires full Xcode.
typealias StoredState<Value> = SwiftUI.State<Value>

enum CompositionFormat: String, CaseIterable, Identifiable {
    case adaptive = "Automatico"
    case portrait = "Verticale 9:16"
    case square = "Quadrato 1:1"
    case landscape = "Orizzontale 16:9"

    var id: String { rawValue }
    var exportSize: CGSize? {
        switch self {
        case .adaptive: return nil
        case .portrait: return CGSize(width:1080,height:1920)
        case .square: return CGSize(width:1080,height:1080)
        case .landscape: return CGSize(width:1920,height:1080)
        }
    }

    /// Fit the complete composition inside the preview, keeping annotations in canvas coordinates.
    func fittedSize(in available: CGSize) -> CGSize {
        guard let size = exportSize else { return available }
        let scale = min(available.width / size.width, available.height / size.height)
        return CGSize(width:size.width * scale,height:size.height * scale)
    }
}

struct StudioCanvas: View {
    @ObservedObject private var localization = AppLocalization.shared
    var image: NSImage?
    var demo: Bool
    var backdrop: Backdrop
    var frame: Bool
    var rotation: Int
    var flipped: Bool
    var zoom: Double
    var grid: Bool
    var marks: [Mark]
    var annotationMode: Bool
    var onPoint: ((CGPoint,Bool) -> Void)?
    var format: CompositionFormat = .adaptive
    var privacyMasks: [PrivacyMask] = []
    @StoredState private var drawing = false
    var body: some View {
        GeometryReader { geometry in
            let canvasSize = format.fittedSize(in:geometry.size)
            ZStack {
                LinearGradient(colors:backdrop.colors,startPoint:.topLeading,endPoint:.bottomTrailing)
                if image != nil || demo {
                    let ratio = image.map { aspect($0) } ?? 0.49
                    let turned = rotation % 2 != 0
                    let availableW = max(1,canvasSize.width * 0.86)
                    let availableH = max(1,canvasSize.height * 0.84)
                    let orientedRatio = turned ? 1/ratio : ratio
                    let fitW = min(availableW,availableH * orientedRatio)
                    let fitH = fitW/orientedRatio
                    let sourceW = turned ? fitH : fitW
                    let sourceH = turned ? fitW : fitH
                    ZStack {
                        RoundedRectangle(cornerRadius:frame ? sourceW*0.09 : 0).fill(Color(white:0.075))
                        Group {
                            if let image, let redacted = PrivacyRenderer.redactedImage(image, masks: privacyMasks) {
                                Image(nsImage:redacted).resizable().aspectRatio(contentMode:.fit)
                            }
                            else if image != nil { Color.black }
                            else { DemoScreen() }
                        }
                        .clipShape(RoundedRectangle(cornerRadius:frame ? sourceW*0.065 : 0))
                        .padding(frame ? sourceW*0.025 : 0)
                    }
                    .frame(width:sourceW,height:sourceH)
                    .overlay(RoundedRectangle(cornerRadius:frame ? sourceW*0.09 : 0).stroke(.white.opacity(frame ? 0.3 : 0),lineWidth:1))
                    .rotationEffect(.degrees(Double(rotation)*90))
                    .scaleEffect(x:flipped ? -zoom : zoom,y:zoom)
                    .shadow(color:.black.opacity(0.35),radius:24,x:0,y:16)
                }
                if grid {
                    Path { path in
                        for x in 1...2 { let pos = canvasSize.width*CGFloat(x)/3; path.move(to:CGPoint(x:pos,y:0)); path.addLine(to:CGPoint(x:pos,y:canvasSize.height)) }
                        for y in 1...2 { let pos = canvasSize.height*CGFloat(y)/3; path.move(to:CGPoint(x:0,y:pos)); path.addLine(to:CGPoint(x:canvasSize.width,y:pos)) }
                    }.stroke(.white.opacity(0.22),style:StrokeStyle(lineWidth:1,dash:[4,5]))
                }
                ForEach(marks) { mark in
                    Path { path in
                        guard let first = mark.points.first else { return }
                        let start = CGPoint(x:first.x*canvasSize.width,y:first.y*canvasSize.height)
                        path.move(to:start)
                        if mark.points.count == 1 { path.addLine(to:CGPoint(x:start.x + 0.01,y:start.y)) }
                        for point in mark.points.dropFirst() { path.addLine(to:CGPoint(x:point.x*canvasSize.width,y:point.y*canvasSize.height)) }
                    }.stroke(mark.color,style:StrokeStyle(lineWidth:canvasSize.width*0.005,lineCap:.round,lineJoin:.round))
                }
                if annotationMode {
                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                        let point = CGPoint(x:min(1,max(0,value.location.x/max(1,canvasSize.width))),y:min(1,max(0,value.location.y/max(1,canvasSize.height))))
                        onPoint?(point,!drawing); drawing = true
                    }.onEnded { _ in drawing = false })
                }
            }.frame(width:canvasSize.width,height:canvasSize.height).clipped()
                .position(x:geometry.size.width/2,y:geometry.size.height/2)
        }
    }
}

struct DemoScreen: View {
    var body: some View {
        GeometryReader { geo in
            VStack(alignment:.leading,spacing:12) {
                HStack { Text("9:41").fontWeight(.semibold); Spacer(); Image(systemName:"wifi"); Image(systemName:"battery.100percent") }.font(.system(size:12)).padding(.top,16)
                Spacer(minLength:8)
                Text("MAKE\nROOM.").font(.system(size:max(24,geo.size.width*0.15),weight:.bold,design:.rounded)).tracking(-1).fixedSize(horizontal:false,vertical:true)
                Text("Your ideas deserve\na bigger screen.").font(.system(size:max(10,geo.size.width*0.048))).lineSpacing(5).foregroundStyle(.white.opacity(0.7))
                ZStack { Circle().fill(LinearGradient(colors:[.mint,.cyan.opacity(0.1)],startPoint:.topLeading,endPoint:.bottomTrailing)); Image(systemName:"sparkle").font(.system(size:geo.size.width*0.2,weight:.ultraLight)).foregroundStyle(.white) }.frame(height:geo.size.height*0.28)
                HStack { Text("SPECCHIO").font(.system(size:11,weight:.bold,design:.monospaced)).tracking(2); Spacer(); Image(systemName:"arrow.up.right") }
                Text("DEMO · NO DEVICE CONNECTED").font(.system(size:8,design:.monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength:12)
                Capsule().fill(.white).frame(width:70,height:4).frame(maxWidth:.infinity).padding(.bottom,8)
            }.padding(.horizontal,22).foregroundStyle(.white).background(LinearGradient(colors:[Color(red:0.08,green:0.18,blue:0.21),Color(red:0.04,green:0.075,blue:0.11)],startPoint:.topLeading,endPoint:.bottomTrailing))
        }
    }
}
