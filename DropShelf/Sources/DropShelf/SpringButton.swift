import AppKit

/// A button that reacts physically: it swells slightly under the pointer and
/// squashes when pressed, settling with a spring rather than a linear ramp.
///
/// Scaling is done with a centred `CATransform3D` instead of moving the
/// layer's `anchorPoint`, because AppKit resets `anchorPoint` and `position`
/// during layout and would fight us for it.
class SpringButton: NSButton {

    /// Scale applied while the pointer is inside.
    var hoverScale: CGFloat = 1.10
    /// Scale applied while the mouse is held down.
    var pressScale: CGFloat = 0.90

    var restingBackground: NSColor = .clear { didSet { applyBackground(animated: false) } }
    var hoverBackground: NSColor = .clear

    /// Subclasses that paint their own shape in `draw(_:)` set this, so the
    /// layer does not also fill a rectangle behind it.
    var drawsOwnBackground = false

    private(set) var isHovered = false
    private(set) var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        wantsLayer = true
        isBordered = false
        setButtonType(.momentaryChange)
        layer?.masksToBounds = false
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        applyState()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        applyState()
        // NSButton's mouseDown runs its own tracking loop and only returns once
        // the mouse is released, so the release animation goes after it.
        super.mouseDown(with: event)
        isPressed = false
        applyState()
    }

    // MARK: Animation

    private var targetScale: CGFloat {
        if isPressed { return pressScale }
        if isHovered { return hoverScale }
        return 1
    }

    func applyState() {
        animateScale(to: targetScale)
        applyBackground(animated: true)
        needsDisplay = true
    }

    private func centredScale(_ scale: CGFloat) -> CATransform3D {
        let w = bounds.width, h = bounds.height
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, w / 2, h / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -w / 2, -h / 2, 0)
        return transform
    }

    private func animateScale(to scale: CGFloat) {
        guard let layer else { return }
        let target = centredScale(scale)

        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 0.7
        // Pressing should feel immediate; releasing should overshoot a little.
        spring.stiffness = isPressed ? 420 : 300
        spring.damping = isPressed ? 22 : 13
        spring.initialVelocity = 0
        spring.fromValue = layer.presentation()?.transform ?? layer.transform
        spring.toValue = target
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = true

        layer.add(spring, forKey: "springScale")
        layer.transform = target
    }

    private func applyBackground(animated: Bool) {
        guard !drawsOwnBackground, let layer else { return }
        let target = (isHovered ? hoverBackground : restingBackground).cgColor
        guard animated else {
            layer.backgroundColor = target
            return
        }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        fade.toValue = target
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "backgroundFade")
        layer.backgroundColor = target
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// The card's ✕ and ⋯ — a bold glyph on a translucent disc.
///
/// The disc is drawn here rather than left to the layer's `cornerRadius`. A
/// radius computed from the initial frame silently stops being a circle the
/// moment Auto Layout hands the button a different size, and an `NSButton`
/// cell's own background drawing does not respect it either. Drawing an oval
/// inscribed in the bounds is correct at any size.
final class CircleGlyphButton: SpringButton {

    private let symbolName: String
    private let glyphPointSize: CGFloat

    init(symbol: String, tooltip: String, diameter: CGFloat, pointSize: CGFloat = 11) {
        self.symbolName = symbol
        self.glyphPointSize = pointSize
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        title = ""
        imagePosition = .imageOnly
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        translatesAutoresizingMaskIntoConstraints = false
        drawsOwnBackground = true
        restingBackground = NSColor.labelColor.withAlphaComponent(0.18)
        hoverBackground = NSColor.labelColor.withAlphaComponent(0.30)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Deliberately bypasses `super.draw`, so the cell never paints a bezel or
    /// background underneath the disc.
    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let disc = NSRect(x: bounds.midX - side / 2,
                          y: bounds.midY - side / 2,
                          width: side,
                          height: side)

        (isHovered ? hoverBackground : restingBackground).setFill()
        NSBezierPath(ovalIn: disc).fill()

        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return
        }
        // Medium, not bold: Dropover's glyphs are noticeably light-stroked.
        let configuration = NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .medium)
        let glyph = (symbol.withSymbolConfiguration(configuration) ?? symbol)
            .tinted(with: isPressed ? .secondaryLabelColor : .labelColor)

        // Inset keeps the glyph comfortably inside the disc at any diameter.
        glyph.drawAspectFit(in: disc.insetBy(dx: side * 0.28, dy: side * 0.28))
    }
}

extension NSImage {
    /// Flattens a template symbol into a solid-coloured image, because a
    /// template is only auto-tinted when a cell draws it, not on manual draw.
    /// Uses the drawing-handler initialiser rather than `lockFocus`, because
    /// the handler is re-invoked per backing scale factor — a `lockFocus`
    /// bitmap would be rasterised at 1× and look soft on a Retina display.
    func tinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { [weak self] rect in
            guard let self else { return false }
            color.set()
            self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}

/// The card's bottom capsule: a label plus a chevron inside its own lighter
/// disc at the trailing end, as in the reference screenshot ("2 Images ›").
final class PillButton: SpringButton {

    private var pillText: String = ""
    private var chevronDown = true

    private static let height: CGFloat = 24
    private static let knobDiameter: CGFloat = 18
    private static let leadingPad: CGFloat = 10
    private static let trailingPad: CGFloat = 3
    private static let gap: CGFloat = 6
    private static let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 110, height: PillButton.height))
        translatesAutoresizingMaskIntoConstraints = false
        hoverScale = 1.05
        pressScale = 0.95
        drawsOwnBackground = true
        restingBackground = NSColor.labelColor.withAlphaComponent(0.14)
        hoverBackground = NSColor.labelColor.withAlphaComponent(0.24)
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let text = (pillText as NSString).size(withAttributes: [.font: Self.font]).width
        let width = Self.leadingPad + text + Self.gap + Self.knobDiameter + Self.trailingPad
        return NSSize(width: min(176, ceil(width)), height: Self.height)
    }

    /// `text` already carries the count and the content noun, e.g. "2 Images".
    func configure(text: String, expanded: Bool) {
        pillText = text
        chevronDown = !expanded
        toolTip = expanded ? "Hide files" : "Show files"
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        (isHovered ? hoverBackground : restingBackground).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (pillText as NSString).size(withAttributes: attributes)
        (pillText as NSString).draw(
            at: NSPoint(x: Self.leadingPad, y: bounds.midY - textSize.height / 2),
            withAttributes: attributes)

        // Chevron knob: its own lighter disc at the trailing end.
        let knob = NSRect(x: bounds.maxX - Self.trailingPad - Self.knobDiameter,
                          y: bounds.midY - Self.knobDiameter / 2,
                          width: Self.knobDiameter,
                          height: Self.knobDiameter)
        NSColor.labelColor.withAlphaComponent(isHovered ? 0.34 : 0.24).setFill()
        NSBezierPath(ovalIn: knob).fill()

        let symbolName = chevronDown ? "chevron.down" : "chevron.up"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)) ?? symbol
            configured.tinted(with: .labelColor)
                .drawAspectFit(in: knob.insetBy(dx: Self.knobDiameter * 0.28,
                                                dy: Self.knobDiameter * 0.28))
        }
    }
}
