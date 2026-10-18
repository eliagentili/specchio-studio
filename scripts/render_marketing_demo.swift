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
        for (name, format) in [("format-portrait", CompositionFormat.portrait),
                               ("format-square", .square), ("format-landscape", .landscape)] {
            let size = format.exportSize!
            let view = StudioCanvas(image: nil, demo: true, backdrop: .aurora, frame: true,
                rotation: 0, flipped: false, zoom: 1, grid: false, marks: [],
                annotationMode: false, onPoint: nil, format: format)
                .frame(width: size.width, height: size.height).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 0.5
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Demo composition rendering failed")
            }
            try data.write(to: destination.appendingPathComponent(name + ".png"))
            print("Rendered \(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
    }
}
