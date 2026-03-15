import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/generate_icon.swift <output_png_path>\n", stderr)
    exit(2)
}

let outputPath = CommandLine.arguments[1]
let canvasSize = CGFloat(1024)
let rect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

let image = NSImage(size: rect.size)
image.lockFocus()

NSColor(calibratedWhite: 0.08, alpha: 1.0).setFill()
rect.fill()

let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 60, dy: 60), xRadius: 220, yRadius: 220)
let backgroundGradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.62, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.78, alpha: 1.0)
    ]
)!
backgroundGradient.draw(in: backgroundPath, angle: -35)

let flare = NSBezierPath(ovalIn: NSRect(x: 140, y: 660, width: 360, height: 220))
NSColor(calibratedRed: 0.93, green: 0.98, blue: 1.0, alpha: 0.22).setFill()
flare.fill()

let cameraBody = NSBezierPath(
    roundedRect: NSRect(x: 210, y: 290, width: 604, height: 430),
    xRadius: 96,
    yRadius: 96
)
NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
cameraBody.fill()

let topBand = NSBezierPath(
    roundedRect: NSRect(x: 280, y: 650, width: 210, height: 95),
    xRadius: 44,
    yRadius: 44
)
NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
topBand.fill()

let lensOuterRect = NSRect(x: 325, y: 360, width: 374, height: 374)
let lensOuter = NSBezierPath(ovalIn: lensOuterRect)
NSColor(calibratedRed: 0.13, green: 0.26, blue: 0.58, alpha: 0.9).setFill()
lensOuter.fill()

let lensInnerRect = lensOuterRect.insetBy(dx: 72, dy: 72)
let lensInner = NSBezierPath(ovalIn: lensInnerRect)
let lensGradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.30, alpha: 1.0),
        NSColor(calibratedRed: 0.21, green: 0.59, blue: 0.82, alpha: 1.0)
    ]
)!
lensGradient.draw(in: lensInner, angle: -35)

let lensSpark = NSBezierPath(ovalIn: NSRect(x: 442, y: 556, width: 88, height: 88))
NSColor(calibratedWhite: 1.0, alpha: 0.34).setFill()
lensSpark.fill()

let tagBubble = NSBezierPath(roundedRect: NSRect(x: 560, y: 290, width: 254, height: 118), xRadius: 36, yRadius: 36)
NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.42, alpha: 0.9).setFill()
tagBubble.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 68, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.95),
    .paragraphStyle: paragraph
]
let text = NSString(string: "TXT")
text.draw(in: NSRect(x: 560, y: 306, width: 254, height: 88), withAttributes: attrs)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode png icon\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("failed writing icon png: \(error)\n", stderr)
    exit(1)
}
