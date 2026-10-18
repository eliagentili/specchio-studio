// SPDX-License-Identifier: GPL-3.0-or-later
// Compile with Sources/*.swift and -D STUDIO_TEST to render the real demo canvas.
// This does not simulate application chrome or a connected physical device.
import SwiftUI
import AppKit

@main struct MarketingDemoRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let heroURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Anteprima-demo.png")
        let outputs: [(URL, CompositionFormat, CGSize, CGFloat)] = [
            (heroURL, .adaptive, CGSize(width: 1000, height: 1200), 1),
            (destination.appendingPathComponent("format-portrait.png"), .portrait,
             CompositionFormat.portrait.exportSize!, 0.5),
            (destination.appendingPathComponent("format-square.png"), .square,
             CompositionFormat.square.exportSize!, 0.5),
            (destination.appendingPathComponent("format-landscape.png"), .landscape,
             CompositionFormat.landscape.exportSize!, 0.5)
        ]
        for (url, format, size, scale) in outputs {
            let view = StudioCanvas(image: nil, demo: true, backdrop: .aurora, frame: true,
                rotation: 0, flipped: false, zoom: 1, grid: false, marks: [],
                annotationMode: false, onPoint: nil, format: format)
                .frame(width: size.width, height: size.height).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Demo composition rendering failed")
            }
            try data.write(to: url)
            print("Rendered \(url.lastPathComponent): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
    }
}
