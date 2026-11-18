import AppKit

/// Borderless, non-activating floating panel.
///
/// Non-activating matters: a shelf must be able to appear *during* a drag
/// without stealing focus from the app the user dragged out of.
final class ShelfPanel: NSPanel {

    init(contentRect: NSRect, restrictToSpace: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Deliberately OFF. Drag-by-background is decided by the hit view's
        // `mouseDownCanMoveWindow` *before* the view receives mouseDragged, so
        // leaving it on makes the window steal every drag that starts on an
        // item — the shelf would slide around instead of dragging content out.
        // Window moves are driven explicitly via `performDrag(with:)` instead.
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        worksWhenModal = true
        isReleasedWhenClosed = false
        collectionBehavior = ShelfPanel.behavior(restrictToSpace: restrictToSpace)
        // Keep the panel out of the window menu / cycling.
        isExcludedFromWindowsMenu = true
    }

    static func behavior(restrictToSpace: Bool) -> NSWindow.CollectionBehavior {
        restrictToSpace
            ? [.moveToActiveSpace, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Borderless windows swallow ⌘-key equivalents by default; forward the
    /// standard editing ones so the title field behaves normally.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers {
            let selector: Selector?
            switch chars {
            case "x": selector = #selector(NSText.cut(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "v": selector = #selector(NSText.paste(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = #selector(UndoManager.undo)
            default: selector = nil
            }
            if let selector, NSApp.sendAction(selector, to: firstResponder, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The blurred shelf backdrop. It is transparent to the mouse so clicks land on
/// `ShelfRootView` below it, which owns the window-drag and edge-double-click
/// behaviour.
final class ShelfBackgroundView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// The shelf's background. This is the only registered dragging destination in
/// the window, so a drop anywhere — including over the item list — lands here.
final class ShelfRootView: NSView {

    weak var controller: ShelfWindowController?

    private var isDropTargeted = false {
        didSet { if oldValue != isDropTargeted { needsDisplay = true } }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes(ShelfItem.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Drop highlight

    /// Corner radius must match the layer's, or the border will not sit on the
    /// clipped edge.
    var cornerRadius: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        // Hairline edge, so the panel reads as a surface against any wallpaper.
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius - 0.5,
                                yRadius: cornerRadius - 0.5)
        edge.lineWidth = 1
        NSColor.separatorColor.setStroke()
        edge.stroke()

        guard isDropTargeted else { return }

        let accent = controller?.shelf.color ?? .controlAccentColor
        let inset = bounds.insetBy(dx: 2, dy: 2)
        let highlight = NSBezierPath(roundedRect: inset,
                                     xRadius: cornerRadius - 2,
                                     yRadius: cornerRadius - 2)
        accent.withAlphaComponent(0.12).setFill()
        highlight.fill()
        highlight.lineWidth = 2.5
        accent.withAlphaComponent(0.95).setStroke()
        highlight.stroke()
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard controller != nil else { return [] }
        isDropTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !ShelfItem.items(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargeted = false
        let items = ShelfItem.items(from: sender.draggingPasteboard)
        guard !items.isEmpty, let controller else { return false }
        controller.add(items: items)
        return true
    }

    // MARK: Edge double-click
    //
    // Mirrors `preferences.double-click-edges`: double-clicking the left or
    // right 10pt of the shelf docks or retracts it.

    private static let edgeWidth: CGFloat = 10

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let controller else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let onLeft = point.x <= Self.edgeWidth
        let onRight = point.x >= bounds.maxX - Self.edgeWidth

        if event.clickCount == 2, onLeft || onRight {
            switch Preferences.shared.edgeDoubleClickAction {
            case .dock:
                if controller.shelf.dockedEdge != nil {
                    controller.undock()
                } else {
                    controller.dock(to: onLeft ? .left : .right)
                }
                return
            case .retract:
                controller.toggleRetracted()
                return
            case .none:
                break
            }
        }

        // Anywhere else on the chrome moves the shelf.
        window?.performDrag(with: event)
    }
}
