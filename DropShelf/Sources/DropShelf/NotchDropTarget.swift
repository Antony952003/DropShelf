import AppKit

/// The MacBook-notch drop target (`preferences.shelf.notch-drag`).
///
/// A transparent always-on-top panel sits over the notch (or, on a screen
/// without one, over a strip at the top centre). It appears while a drag is in
/// flight and turns a drop into a new shelf. Highlighting follows the three
/// observed modes: always, on hover, or never.
final class NotchDropController {
    static let shared = NotchDropController()

    private var panel: NSPanel?
    private var dropView: NotchDropView?

    private static let fallbackSize = CGSize(width: 200, height: 26)

    private init() {}

    func setDragActive(_ active: Bool) {
        guard Preferences.shared.notchEnabled else {
            hide()
            return
        }
        active ? show() : hide()
    }

    // MARK: Geometry

    /// The notch rect on `screen`, or `nil` when the screen has no notch.
    static func notchRect(for screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let x = left.maxX
        let width = right.minX - x
        guard width > 2 else { return nil }
        return CGRect(x: x, y: left.minY, width: width, height: left.height)
    }

    private static func targetRect() -> (CGRect, NSScreen)? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        if let notch = notchRect(for: screen) {
            return (notch, screen)
        }
        let size = fallbackSize
        let rect = CGRect(x: screen.frame.midX - size.width / 2,
                          y: screen.frame.maxY - size.height,
                          width: size.width,
                          height: size.height)
        return (rect, screen)
    }

    // MARK: Show / hide

    private func show() {
        guard let (rect, _) = Self.targetRect() else { return }

        if panel == nil {
            let newPanel = NSPanel(contentRect: rect,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.ignoresMouseEvents = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.isReleasedWhenClosed = false

            let view = NotchDropView(frame: NSRect(origin: .zero, size: rect.size))
            newPanel.contentView = view
            dropView = view
            panel = newPanel
        }

        panel?.setFrame(rect, display: false)
        dropView?.isDragActive = true
        panel?.orderFrontRegardless()
    }

    private func hide() {
        dropView?.isDragActive = false
        panel?.orderOut(nil)
    }

    /// Called by the drop view once content lands on the notch.
    func didReceive(items: [ShelfItem]) {
        hide()
        guard !items.isEmpty, let (rect, _) = Self.targetRect() else { return }
        // Place the shelf just below the notch.
        let point = CGPoint(x: rect.midX, y: rect.minY - 140)
        ShelfStore.shared.createShelf(at: point, items: items)
    }
}

final class NotchDropView: NSView {

    var isDragActive = false {
        didSet { needsDisplay = true }
    }

    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes(ShelfItem.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    private var shouldHighlight: Bool {
        guard isDragActive else { return false }
        switch Preferences.shared.notchHighlight {
        case .always: return true
        case .hover: return isTargeted || isHovering
        case .never: return false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard shouldHighlight else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(isTargeted ? 0.85 : 0.45).setFill()
        path.fill()

        if let symbol = NSImage(systemSymbolName: "tray.and.arrow.down.fill",
                                accessibilityDescription: nil) {
            let side = min(14, rect.height - 6)
            let iconRect = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                                  width: side, height: side)
            NSColor.white.set()
            symbol.isTemplate = true
            symbol.draw(in: iconRect)
        }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !ShelfItem.items(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let items = ShelfItem.items(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        NotchDropController.shared.didReceive(items: items)
        return true
    }
}
