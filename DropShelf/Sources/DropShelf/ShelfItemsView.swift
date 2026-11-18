import AppKit

/// The body of a shelf: draws items either as an icon grid or as a list, and
/// is the dragging *source* for everything on the shelf.
///
/// Dropover splits these into `DragSessionGridViewController` and
/// `DragSessionListViewController` (ANALYSIS.md §3). One view with two layout
/// strategies is the same behaviour with far less plumbing.
final class ShelfItemsView: NSView, NSDraggingSource {

    weak var controller: ShelfWindowController?

    var layout: ShelfLayout = .grid {
        didSet {
            guard oldValue != layout else { return }
            invalidateLayout()
        }
    }

    /// Parked/collapsed shelves draw the items as a fanned pile instead of a
    /// grid or list — Dropover's collapsed-card look.
    var isCollapsed = false {
        didSet {
            guard oldValue != isCollapsed else { return }
            invalidateLayout()
        }
    }

    private(set) var selection: Set<UUID> = []
    private var hoveredIndex: Int?
    private var mouseDownPoint: NSPoint?
    private var mouseDownIndex: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Must be false: otherwise AppKit hands a mouse-down on an item to the
    /// window's drag-by-background machinery and this view never receives
    /// `mouseDragged`, so the shelf slides instead of the content dragging out.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Metrics

    private enum Metrics {
        static let gridCell = CGSize(width: 84, height: 100)
        static let gridInset: CGFloat = 10
        static let gridSpacing: CGFloat = 4
        static let gridIcon: CGFloat = 52
        static let rowHeight: CGFloat = 44
        static let listInset: CGFloat = 6
        static let listIcon: CGFloat = 30
        static let stackInset: CGFloat = 18
        static let stackMaxVisible = 4
    }

    private var items: [ShelfItem] { controller?.shelf.items ?? [] }

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private var columns: Int {
        let usable = bounds.width - Metrics.gridInset * 2
        let per = Metrics.gridCell.width + Metrics.gridSpacing
        return max(1, Int((usable + Metrics.gridSpacing) / per))
    }

    /// Height this view needs for the current item count.
    func requiredHeight(forWidth width: CGFloat) -> CGFloat {
        let count = items.count
        guard count > 0 else { return 0 }
        if isCollapsed { return 0 } // fills the clip view; never scrolls
        switch layout {
        case .grid:
            let usable = width - Metrics.gridInset * 2
            let per = Metrics.gridCell.width + Metrics.gridSpacing
            let cols = max(1, Int((usable + Metrics.gridSpacing) / per))
            let rows = Int(ceil(Double(count) / Double(cols)))
            return Metrics.gridInset * 2 + CGFloat(rows) * Metrics.gridCell.height
        case .list:
            return Metrics.listInset * 2 + CGFloat(count) * Metrics.rowHeight
        }
    }

    func invalidateLayout() {
        let width = (superview as? NSClipView)?.bounds.width ?? bounds.width
        let height = max(requiredHeight(forWidth: width),
                         (superview as? NSClipView)?.bounds.height ?? 0)
        setFrameSize(NSSize(width: width, height: height))
        rebuildTrackingAreas()
        needsDisplay = true
    }

    /// Brief springy swell, used when new content lands on the shelf.
    func pulse() {
        guard let layer else { return }
        let w = bounds.width, h = bounds.height
        func scale(_ s: CGFloat) -> CATransform3D {
            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, w / 2, h / 2, 0)
            t = CATransform3DScale(t, s, s, 1)
            return CATransform3DTranslate(t, -w / 2, -h / 2, 0)
        }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 0.8
        spring.stiffness = 220
        spring.damping = 11
        spring.fromValue = scale(1.08)
        spring.toValue = CATransform3DIdentity
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pulse")
    }

    func reload() {
        selection = selection.filter { id in items.contains { $0.id == id } }
        invalidateLayout()
    }

    /// Where the fanned pile is drawn, and the hit area for dragging it out.
    private var stackBox: NSRect {
        let available = bounds.insetBy(dx: Metrics.stackInset, dy: Metrics.stackInset)
        let side = max(0, min(available.width, available.height))
        return NSRect(x: bounds.midX - side / 2,
                      y: available.midY - side / 2,
                      width: side,
                      height: side)
    }

    func frame(forItemAt index: Int) -> NSRect {
        if isCollapsed { return stackBox }
        switch layout {
        case .grid:
            let cols = columns
            let row = index / cols
            let col = index % cols
            return NSRect(x: Metrics.gridInset + CGFloat(col) * (Metrics.gridCell.width + Metrics.gridSpacing),
                          y: Metrics.gridInset + CGFloat(row) * Metrics.gridCell.height,
                          width: Metrics.gridCell.width,
                          height: Metrics.gridCell.height)
        case .list:
            return NSRect(x: Metrics.listInset,
                          y: Metrics.listInset + CGFloat(index) * Metrics.rowHeight,
                          width: max(0, bounds.width - Metrics.listInset * 2),
                          height: Metrics.rowHeight)
        }
    }

    private func index(at point: NSPoint) -> Int? {
        if isCollapsed {
            // The pile behaves as one object: hitting it means "all items".
            return (!items.isEmpty && stackBox.contains(point)) ? 0 : nil
        }
        for i in items.indices where frame(forItemAt: i).contains(point) { return i }
        return nil
    }

    // MARK: Tracking

    private func rebuildTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                       owner: self,
                                       userInfo: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let new = index(at: convert(event.locationInWindow, from: nil))
        if new != hoveredIndex {
            hoveredIndex = new
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
        }
    }

    // MARK: Selection

    var selectedItems: [ShelfItem] {
        items.filter { selection.contains($0.id) }
    }

    func selectAllItems() {
        selection = Set(items.map(\.id))
        needsDisplay = true
    }

    func clearSelection() {
        selection.removeAll()
        needsDisplay = true
    }

    private func select(index: Int, event: NSEvent) {
        guard items.indices.contains(index) else { return }
        let id = items[index].id
        if event.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if event.modifierFlags.contains(.shift), let anchor = lastSelectedIndex {
            let range = min(anchor, index)...max(anchor, index)
            selection.formUnion(range.map { items[$0].id })
        } else {
            selection = [id]
        }
        lastSelectedIndex = index
        needsDisplay = true
        controller?.selectionDidChange()
    }

    private var lastSelectedIndex: Int?

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        let hit = index(at: point)
        mouseDownPoint = point
        mouseDownIndex = hit

        guard let hit else {
            // Empty space: clear the selection, then either let the root view
            // handle an edge double-click or move the shelf.
            clearSelection()
            controller?.selectionDidChange()
            if event.clickCount == 2 {
                super.mouseDown(with: event)
            } else {
                window?.performDrag(with: event)
            }
            return
        }

        if event.clickCount == 2 {
            controller?.open(items: [items[hit]])
            return
        }

        // Don't collapse a multi-selection on the mouse-down that starts a drag.
        if !selection.contains(items[hit].id) || event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.shift) {
            select(index: hit, event: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, mouseDownIndex != nil else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        beginDragOut(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        mouseDownIndex = nil
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = index(at: point), !selection.contains(items[hit].id) {
            selection = [items[hit].id]
            lastSelectedIndex = hit
            needsDisplay = true
            controller?.selectionDidChange()
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.actionMenu(for: selectedItems)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if controller?.handleShelfKey(event) == true { return }
        super.keyDown(with: event)
    }

    // MARK: Dragging out

    /// Items being dragged out right now, so the session-end handler knows
    /// what to remove on a `.move`.
    private var draggedItems: [ShelfItem] = []

    private func beginDragOut(with event: NSEvent) {
        guard let controller else { return }
        let dragged: [ShelfItem]
        if isCollapsed {
            dragged = items // the pile drags out as one group
        } else if selectedItems.isEmpty {
            dragged = mouseDownIndex.flatMap { items.indices.contains($0) ? [items[$0]] : nil } ?? []
        } else {
            dragged = selectedItems
        }
        guard !dragged.isEmpty else { return }

        var draggingItems: [NSDraggingItem] = []
        for item in dragged {
            guard let writer = controller.pasteboardWriter(for: item) else { continue }
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let index = items.firstIndex(of: item) ?? 0
            let cell = frame(forItemAt: index)
            let side = isCollapsed
                ? Metrics.gridIcon
                : (layout == .grid ? Metrics.gridIcon : Metrics.listIcon)
            let icon = item.icon(size: side)
            let iconFrame = NSRect(x: cell.midX - icon.size.width / 2,
                                   y: cell.minY + 6,
                                   width: icon.size.width,
                                   height: icon.size.height)
            draggingItem.setDraggingFrame(iconFrame, contents: icon)
            draggingItems.append(draggingItem)
        }
        guard !draggingItems.isEmpty else { return }

        draggedItems = dragged
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.copy, .move, .generic]
        case .outsideApplication:
            // Observed Dropover default: content is *moved*, and the system
            // downgrades to a copy across volumes. "Copy files instead of
            // moving" flips the advertised mask.
            return Preferences.shared.copyInsteadOfMove ? [.copy] : [.move, .copy]
        @unknown default:
            return .copy
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let dragged = draggedItems
        draggedItems = []
        guard !dragged.isEmpty, operation != [] else { return }

        if operation.contains(.move) || operation.contains(.delete) {
            controller?.remove(items: dragged)
        }
        if Preferences.shared.closeAfterDrag {
            controller?.closeShelf()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !items.isEmpty else {
            drawEmptyState()
            return
        }
        if isCollapsed {
            drawCollapsedStack()
            return
        }
        for index in items.indices {
            let cell = frame(forItemAt: index)
            guard cell.intersects(dirtyRect) else { continue }
            draw(item: items[index], at: index, in: cell)
        }
    }

    // MARK: Collapsed pile
    //
    // Up to four items are drawn back-to-front, each one a little smaller,
    // nudged up-left and rotated a touch, so a multi-file shelf reads as a
    // physical stack. A "N Files" pill underneath expands the card.

    private func drawCollapsedStack() {
        let box = stackBox
        guard box.width > 20 else { return }

        let visible = Array(items.prefix(Metrics.stackMaxVisible))

        // Back-to-front, so each card overlaps the one behind it.
        for depth in stride(from: visible.count - 1, through: 0, by: -1) {
            let item = visible[depth]
            let d = CGFloat(depth)

            // Gentle progression: a little smaller, a little higher, a slight
            // tilt that alternates side to side so the pile looks hand-stacked.
            let side = box.width * (1 - d * 0.06)
            let centre = NSPoint(x: box.midX - d * 5, y: box.midY - d * 5)
            let angle = d == 0 ? 0 : (depth % 2 == 0 ? -1 : 1) * (2.5 + d * 1.6)
            let fade = depth == 0 ? 1.0 : max(0.45, 1 - d * 0.2)

            NSGraphicsContext.saveGraphicsState()

            let transform = NSAffineTransform()
            transform.translateX(by: centre.x, yBy: centre.y)
            transform.rotate(byDegrees: angle)
            transform.translateX(by: -centre.x, yBy: -centre.y)
            transform.concat()

            // Soft drop shadow lifts each card off the one behind it.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28 * fade)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1.5)
            shadow.set()

            let rect = NSRect(x: centre.x - side / 2,
                              y: centre.y - side / 2,
                              width: side,
                              height: side)
            drawArtwork(image(for: item, side: side), in: rect, opacity: fade)

            NSGraphicsContext.restoreGraphicsState()
        }

    }

    /// `content.empty-state.title` — "Drop files here", inside a dashed well.
    private func drawEmptyState() {
        let well = bounds.insetBy(dx: 14, dy: 14)
        guard well.width > 60, well.height > 50 else { return }

        let path = NSBezierPath(roundedRect: well, xRadius: 10, yRadius: 10)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.separatorColor.setStroke()
        path.stroke()

        let symbol = NSImage(systemSymbolName: "arrow.down.doc",
                             accessibilityDescription: nil)
        symbol?.isTemplate = true
        let side: CGFloat = 26
        let iconRect = NSRect(x: well.midX - side / 2,
                              y: well.midY - side - 2,
                              width: side, height: side)
        NSColor.tertiaryLabelColor.set()
        symbol?.drawAspectFit(in: iconRect)

        draw(text: "Drop files here",
             in: NSRect(x: well.minX, y: well.midY + 8, width: well.width, height: 18),
             font: .systemFont(ofSize: 11, weight: .medium),
             color: .tertiaryLabelColor,
             lines: 1,
             alignment: .center)
    }

    /// Quick Look preview when we have one, Finder icon otherwise.
    private func image(for item: ShelfItem, side: CGFloat) -> (image: NSImage, isPreview: Bool) {
        if case .file(let url) = item.payload {
            let scale = window?.backingScaleFactor ?? 2
            if let preview = ThumbnailCache.shared.thumbnail(
                for: url, side: side, scale: scale,
                onReady: { [weak self] in self?.needsDisplay = true }) {
                return (preview, true)
            }
        }
        return (item.icon(size: side), false)
    }

    private func draw(item: ShelfItem, at index: Int, in cell: NSRect) {
        let isSelected = selection.contains(item.id)
        let isHovered = hoveredIndex == index

        if isSelected || isHovered {
            let highlight = cell.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: highlight, xRadius: 8, yRadius: 8)
            if isSelected {
                NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
            } else {
                NSColor.quaternaryLabelColor.withAlphaComponent(0.55).setFill()
            }
            path.fill()
        }

        let primaryColor: NSColor = isSelected ? .white : .labelColor
        let secondaryColor: NSColor = isSelected
            ? NSColor.white.withAlphaComponent(0.8)
            : .secondaryLabelColor

        switch layout {
        case .grid:
            let side = Metrics.gridIcon
            let box = NSRect(x: cell.midX - side / 2, y: cell.minY + 9, width: side, height: side)
            let art = image(for: item, side: side)
            drawArtwork(art, in: box)

            let labelRect = NSRect(x: cell.minX + 3,
                                   y: box.maxY + 6,
                                   width: cell.width - 6,
                                   height: 28)
            draw(text: item.displayName,
                 in: labelRect,
                 font: .systemFont(ofSize: 10.5),
                 color: primaryColor,
                 lines: 2,
                 alignment: .center)

        case .list:
            let side = Metrics.listIcon
            let box = NSRect(x: cell.minX + 10, y: cell.midY - side / 2, width: side, height: side)
            let art = image(for: item, side: side)
            drawArtwork(art, in: box)

            let textX = box.maxX + 10
            let width = max(0, cell.maxX - textX - 10)
            draw(text: item.displayName,
                 in: NSRect(x: textX, y: cell.minY + 7, width: width, height: 15),
                 font: .systemFont(ofSize: 12, weight: .medium),
                 color: primaryColor, lines: 1, alignment: .left)
            draw(text: item.subtitle,
                 in: NSRect(x: textX, y: cell.minY + 23, width: width, height: 13),
                 font: .systemFont(ofSize: 10),
                 color: secondaryColor, lines: 1, alignment: .left)
        }
    }

    /// Previews get a hairline frame and rounded corners so a photo reads as a
    /// photo; plain file-type icons are drawn bare.
    private func drawArtwork(_ art: (image: NSImage, isPreview: Bool),
                             in box: NSRect,
                             opacity: CGFloat = 1) {
        NSGraphicsContext.saveGraphicsState()
        if opacity < 1 {
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        guard art.isPreview else {
            art.image.draw(in: art.image.aspectFitRect(in: box),
                           from: .zero,
                           operation: .sourceOver,
                           fraction: opacity)
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        let fitted = art.image.aspectFitRect(in: box)
        let clip = NSBezierPath(roundedRect: fitted, xRadius: 3, yRadius: 3)
        clip.addClip()
        art.image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: opacity)
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(roundedRect: fitted.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: 3, yRadius: 3)
        border.lineWidth = 1
        NSColor.separatorColor.withAlphaComponent(opacity).setStroke()
        border.stroke()
    }

    private func draw(text: String, in rect: NSRect, font: NSFont, color: NSColor,
                      lines: Int, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingMiddle
        paragraph.maximumLineHeight = font.pointSize + 3
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
