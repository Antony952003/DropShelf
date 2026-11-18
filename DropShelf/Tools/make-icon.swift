// Renders DropShelf's app icon into an .iconset directory.
// Usage: swift make-icon.swift <output.iconset>
//
// Everything is drawn here — no bundled artwork.

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: side, height: side)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    let inset = side * 0.08
    let plate = bounds.insetBy(dx: inset, dy: inset)
    let radius = plate.width * 0.235

    // Rounded plate with a vertical gradient.
    let plattePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.52, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.78, alpha: 1.0),
    ])
    gradient?.draw(in: plattePath, angle: -90)

    // Three stacked "cards", the shelf metaphor.
    let cardWidth = plate.width * 0.52
    let cardHeight = plate.height * 0.115
    let centreX = plate.midX
    let baseY = plate.minY + plate.height * 0.22

    for index in 0..<3 {
        let shrink = CGFloat(index) * plate.width * 0.055
        let rect = NSRect(x: centreX - (cardWidth - shrink) / 2,
                          y: baseY + CGFloat(index) * cardHeight * 1.22,
                          width: cardWidth - shrink,
                          height: cardHeight)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: cardHeight * 0.34,
                                yRadius: cardHeight * 0.34)
        NSColor.white.withAlphaComponent(0.40 + 0.22 * CGFloat(index)).setFill()
        path.fill()
    }

    // Downward arrow dropping into the stack.
    let arrowWidth = plate.width * 0.17
    let shaft = NSRect(x: centreX - arrowWidth * 0.26,
                       y: baseY + cardHeight * 4.2,
                       width: arrowWidth * 0.52,
                       height: plate.height * 0.20)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: shaft,
                 xRadius: shaft.width * 0.4,
                 yRadius: shaft.width * 0.4).fill()

    let head = NSBezierPath()
    let headTop = shaft.minY + plate.height * 0.035
    head.move(to: NSPoint(x: centreX - arrowWidth * 0.62, y: headTop))
    head.line(to: NSPoint(x: centreX + arrowWidth * 0.62, y: headTop))
    head.line(to: NSPoint(x: centreX, y: headTop - plate.height * 0.095))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// Sizes iconutil expects.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = render(size: variant.size) else {
        FileHandle.standardError.write("failed rendering \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = outputDirectory.appendingPathComponent("\(variant.name).png")
    try data.write(to: url)
}

print("wrote \(variants.count) icon variants to \(outputDirectory.path)")
