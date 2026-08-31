import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("iconset output path required") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let representations: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in representations {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = CGFloat(size) * 0.055
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()

    let colors = [
        NSColor(calibratedRed: 0.92, green: 0.39, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.67, blue: 0.52, alpha: 1),
        NSColor(calibratedRed: 0.37, green: 0.52, blue: 0.98, alpha: 1)
    ]
    let widths: [CGFloat] = [0.72, 0.54, 0.34]
    let barHeight = CGFloat(size) * 0.105
    let x = CGFloat(size) * 0.20
    for index in 0..<3 {
        let y = CGFloat(size) * (0.65 - CGFloat(index) * 0.19)
        let track = NSRect(x: x, y: y, width: CGFloat(size) * 0.60, height: barHeight)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        colors[index].setFill()
        let fill = NSRect(x: x, y: y, width: CGFloat(size) * 0.60 * widths[index], height: barHeight)
        NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG render failed") }
    try png.write(to: output.appendingPathComponent(name))
}
