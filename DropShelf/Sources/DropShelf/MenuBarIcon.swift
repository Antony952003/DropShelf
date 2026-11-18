import AppKit

/// The menu-bar glyph.
///
/// The default is drawn rather than borrowed from SF Symbols, so the status
/// item echoes the shelf card's fanned pile instead of being a generic tray.
///
/// Everything here is a **template** image: drawn in black with alpha, which
/// lets AppKit invert it for dark menu bars, dim it when the app is inactive,
/// and knock it out to white while the menu is open. Drawing colour explicitly
/// would break all three.
enum MenuBarIcon {

    /// Menu bar glyphs get ~18pt of height to work with.
    private static let canvas = NSSize(width: 18, height: 18)

    static func image(for style: MenuBarIconStyle) -> NSImage? {
        let image: NSImage?
        switch style {
        case .pile:
            image = pile()
        case .shelf:
            image = shelf()
        case .traditional:
            image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropShelf")
        case .document:
            image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "DropShelf")
        }
        image?.isTemplate = true
        return image
    }

    /// Three cards fanned up and to the left, the front one solid. Mirrors the
    /// pile drawn on the shelf card itself.
    private static func pile() -> NSImage {
        NSImage(size: canvas, flipped: false) { _ in
            let card = NSSize(width: 10, height: 7.5)
            let step: CGFloat = 2.6
            // Centre the whole fan inside the canvas.
            let spread = step * 2
            let originX = (canvas.width - card.width - spread) / 2
            let originY = (canvas.height - card.height - spread) / 2

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Back two cards: outlines only, so the stack reads as depth.
            for depth in [2, 1] {
                let offset = CGFloat(depth) * step
                let rect = NSRect(x: originX + offset,
                                  y: originY + offset,
                                  width: card.width,
                                  height: card.height)
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6),
                                        xRadius: 1.8, yRadius: 1.8)
                path.lineWidth = 1.0
                path.stroke()
            }

            // Front card: a heavier outline rather than a solid fill. Filling
            // it pushed ink coverage to ~50%, which reads as a blob at 18pt;
            // menu-bar glyphs are conventionally line art.
            let front = NSRect(x: originX, y: originY, width: card.width, height: card.height)
            let frontPath = NSBezierPath(roundedRect: front.insetBy(dx: 0.8, dy: 0.8),
                                         xRadius: 2, yRadius: 2)
            frontPath.lineWidth = 1.3
            frontPath.stroke()
            return true
        }
    }

    /// A shelf line with content dropping onto it.
    private static func shelf() -> NSImage {
        NSImage(size: canvas, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // The shelf.
            let shelfRect = NSRect(x: 2.5, y: 3.5, width: 13, height: 1.8)
            NSBezierPath(roundedRect: shelfRect, xRadius: 0.9, yRadius: 0.9).fill()

            // Arrow shaft.
            let shaft = NSRect(x: canvas.width / 2 - 0.9, y: 7, width: 1.8, height: 5.5)
            NSBezierPath(roundedRect: shaft, xRadius: 0.9, yRadius: 0.9).fill()

            // Arrow head pointing down at the shelf.
            let head = NSBezierPath()
            head.move(to: NSPoint(x: canvas.width / 2 - 3.6, y: 7.6))
            head.line(to: NSPoint(x: canvas.width / 2 + 3.6, y: 7.6))
            head.line(to: NSPoint(x: canvas.width / 2, y: 6.0 - 1.4))
            head.close()
            head.fill()
            return true
        }
    }
}
