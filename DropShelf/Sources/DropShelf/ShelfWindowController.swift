import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// One shelf: window, chrome, state, and every mutation of its shelf.
///
/// Corresponds to Dropover's `DragSessionOutlineViewController` — title field,
/// grid/list segmented control, bar button, separator, content view
/// (ANALYSIS.md §3) — collapsed into an `NSWindowController` because the
/// rebuild has no storyboard.
final class ShelfWindowController: NSWindowController, NSWindowDelegate {

    let shelf: ShelfDocument

    // Chrome
    private let rootView = ShelfRootView(frame: .zero)
    private let effectView = ShelfBackgroundView()
    private let colorBar = NSView()
    private let barButton = CircleGlyphButton(symbol: "ellipsis", tooltip: "Open Action Menu",
                                              diameter: ShelfWindowController.cardButtonSize)
    private let closeButton = CircleGlyphButton(symbol: "xmark", tooltip: "Close",
                                                diameter: ShelfWindowController.cardButtonSize)
    private let pilePill = PillButton()
    private let scrollView = NSScrollView()
    /// The attached dropdown listing the actual files. Created on first expand.
    private var detailPanel: ShelfDetailPanel?
    private let itemsView = ShelfItemsView(frame: .zero)

    // Geometry constants
    private static let headerHeight: CGFloat = 34
    private static let footerHeight: CGFloat = 18
    /// The colour label is a short centred pill near the top edge, not a
    /// full-width stripe.
    private static let colorPillSize = NSSize(width: 30, height: 4)
    private static let cornerRadius: CGFloat = 20
    static let cardButtonSize: CGFloat = 24
    /// Gap between the card's bottom edge and the dropdown.
    private static let detailGap: CGFloat = 6
    private static let dockTabWidth: CGFloat = 18
    private static let snapDistance: CGFloat = 14

    // Runtime state
    /// Top-left corner the shelf returns to when it is not parked. Size comes
    /// from the presentation, so one anchor point is all that is needed.
    private var restingTopLeft: NSPoint
    private var undockedFrame: NSRect?
    private var isDockRevealed = false
    private var moveDebounce: DispatchWorkItem?
    private var promiseQueue = OperationQueue()
    private var quickLookURLs: [URL] = []
    private(set) var isHovered = false
    /// Set when a shelf is created already holding dropped content (notch
    /// drop, Services, clipboard) — that is still an "initial file drop", so it
    /// should park like any other. Restored shelves leave this false so they
    /// stay where the user left them.
    var parkAfterShowing = false

    // MARK: - Init

    init(shelf: ShelfDocument) {
        self.shelf = shelf
        self.restingTopLeft = NSPoint(x: shelf.frame.minX, y: shelf.frame.maxY)

        let panel = ShelfPanel(contentRect: shelf.frame,
                               restrictToSpace: Preferences.shared.restrictToCurrentSpace)
        super.init(window: panel)
        panel.delegate = self
        panel.styleMask.insert(.resizable)
        panel.minSize = NSSize(width: 220, height: 120)

        buildChrome()
        applyDocumentState()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(preferencesDidChange),
                                               name: Preferences.didChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Chrome construction
    //
    // The card carries only what Dropover's card carries: a colour stripe, a
    // close button top-left, an action button top-right, and the pile. The
    // title, layout switch, count and file list all live in the attached
    // dropdown (`ShelfDetailPanel`).

    private func buildChrome() {
        guard let window else { return }

        rootView.controller = self
        rootView.cornerRadius = Self.cornerRadius
        rootView.frame = NSRect(origin: .zero, size: shelf.frame.size)
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Self.cornerRadius
        rootView.layer?.masksToBounds = true
        window.contentView = rootView

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(effectView)

        colorBar.wantsLayer = true
        colorBar.layer?.cornerRadius = Self.colorPillSize.height / 2
        colorBar.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(colorBar)

        closeButton.target = self
        closeButton.action = #selector(didSelectCloseButton)
        rootView.addSubview(closeButton)

        barButton.target = self
        barButton.action = #selector(didSelectBarButton)
        rootView.addSubview(barButton)

        pilePill.target = self
        pilePill.action = #selector(didSelectPilePill)
        rootView.addSubview(pilePill)

        itemsView.controller = self
        itemsView.isCollapsed = true // the card is always the pile
        scrollView.documentView = itemsView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(scrollView)

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clipViewFrameChanged),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)

        let side = Self.cardButtonSize
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: rootView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            colorBar.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            colorBar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 7),
            colorBar.widthAnchor.constraint(equalToConstant: Self.colorPillSize.width),
            colorBar.heightAnchor.constraint(equalToConstant: Self.colorPillSize.height),

            closeButton.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 9),
            closeButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 11),
            closeButton.widthAnchor.constraint(equalToConstant: side),
            closeButton.heightAnchor.constraint(equalToConstant: side),

            barButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -9),
            barButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            barButton.widthAnchor.constraint(equalToConstant: side),
            barButton.heightAnchor.constraint(equalToConstant: side),

            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: pilePill.topAnchor, constant: -6),

            pilePill.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            pilePill.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -9),
            pilePill.heightAnchor.constraint(equalToConstant: 24),
        ])

        rebuildTracking()
    }

    private func rebuildTracking() {
        for area in rootView.trackingAreas { rootView.removeTrackingArea(area) }
        rootView.addTrackingArea(NSTrackingArea(rect: .zero,
                                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                owner: self,
                                                userInfo: nil))
    }


    // MARK: - Showing

    func showShelf() {
        guard let window else { return }
        restingTopLeft = NSPoint(x: shelf.frame.minX, y: shelf.frame.maxY)
        let target = frameForCurrentState()
        // Pop in from slightly undersized rather than just fading.
        let start = target.insetBy(dx: target.width * 0.05, dy: target.height * 0.05)
        window.setFrame(start, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = Self.easing
            window.animator().alphaValue = 1
            window.animator().setFrame(target, display: true)
        }
        refresh()
        if let edge = shelf.dockedEdge {
            dock(to: edge, animated: false)
        } else if parkAfterShowing && Preferences.shared.autoRetract {
            parkAfterShowing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.setParked(true)
            }
        }
    }

    func closeShelf() {
        guard let window else { return }
        syncDocumentFrame()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.hideDetailPanel()
            window.orderOut(nil)
            ShelfStore.shared.didClose(self)
        }
    }

    // MARK: - State → UI

    private func applyDocumentState() {
        itemsView.layout = shelf.layout
        colorBar.isHidden = !Preferences.shared.useColorLabels
        colorBar.layer?.backgroundColor = shelf.color.cgColor
        window?.collectionBehavior = ShelfPanel.behavior(
            restrictToSpace: Preferences.shared.restrictToCurrentSpace)
    }

    func refresh() {
        applyDocumentState()
        pilePill.configure(text: pillTitle(), expanded: shelf.isExpanded)
        // Materialise the dropdown if the shelf is expanded but has none yet —
        // which is the case for a pinned shelf restored in the expanded state.
        if shelf.isExpanded {
            if detailPanel?.parent != nil { repositionDetailPanel() } else { showDetailPanel() }
        } else {
            hideDetailPanel()
        }
        itemsView.reload()
        updateFooter()
        ShelfStore.shared.notifyChange()
    }

    private func updateFooter() {
        detailPanel?.updateCountLabel()
    }

    /// "2 Images", "1 Folder", "3 Files" — the reference card names the kind of
    /// content it holds, not just "Files".
    func pillTitle() -> String {
        let items = shelf.items
        guard !items.isEmpty else { return "Empty" }

        func kind(of item: ShelfItem) -> String {
            switch item.payload {
            case .image: return "image"
            case .plainText, .richText: return "text"
            case .webURL: return "link"
            case .file(let url):
                if url.isDirectory { return "folder" }
                if let type = UTType(filenameExtension: url.pathExtension),
                   type.conforms(to: .image) { return "image" }
                if let type = UTType(filenameExtension: url.pathExtension),
                   type.conforms(to: .movie) { return "video" }
                return "file"
            }
        }

        let kinds = Set(items.map(kind(of:)))
        let key = kinds.count == 1 ? (kinds.first ?? "file") : "file"
        let singular = ["image": "Image", "folder": "Folder", "file": "File",
                        "text": "Text", "link": "Link", "video": "Video"]
        let plural = ["image": "Images", "folder": "Folders", "file": "Files",
                      "text": "Texts", "link": "Links", "video": "Videos"]
        let noun = items.count == 1 ? (singular[key] ?? "File") : (plural[key] ?? "Files")
        return "\(items.count) \(noun)"
    }

    func selectionDidChange() {
        updateFooter()
    }

    @objc private func preferencesDidChange() {
        applyDocumentState()
    }

    @objc private func clipViewFrameChanged() {
        itemsView.invalidateLayout()
    }

    // MARK: - Document mutation

    func add(items newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        let existingFiles = Set(shelf.items.compactMap { item -> String? in
            if case .file(let url) = item.payload { return url.path }
            return nil
        })
        let deduped = newItems.filter { item in
            if case .file(let url) = item.payload { return !existingFiles.contains(url.path) }
            return true
        }
        guard !deduped.isEmpty else { return }

        shelf.items.append(contentsOf: deduped)
        let isFirstDrop = !shelf.hasReceivedDrop
        shelf.hasReceivedDrop = true
        refresh()
        itemsView.pulse()

        // Park it regardless of where the pointer is: the user has just
        // dropped onto the shelf, so the cursor is necessarily over it, and
        // getting out of the way is the whole point of the setting.
        if isFirstDrop && Preferences.shared.autoRetract {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.setParked(true)
            }
        }
    }

    func remove(items: [ShelfItem]) {
        let ids = Set(items.map(\.id))
        shelf.items.removeAll { ids.contains($0.id) }
        refresh()
    }

    func clear() {
        shelf.items.removeAll()
        refresh()
    }

    func setLayout(_ layout: ShelfLayout) {
        shelf.layout = layout
        itemsView.layout = layout
        repositionDetailPanel()
        itemsView.invalidateLayout()
        ShelfStore.shared.notifyChange()
    }

    /// Persist the shelf's resting geometry: the expanded size plus the
    /// top-left it returns to. Parked and docked positions are transient.
    func syncDocumentFrame() {
        guard let window else { return }
        if let undockedFrame {
            shelf.frame = undockedFrame
            return
        }
        var frame = shelf.frame
        if shelf.isExpanded && !shelf.isParked {
            frame.size = window.frame.size
        }
        frame.origin = NSPoint(x: restingTopLeft.x, y: restingTopLeft.y - frame.height)
        shelf.frame = frame
    }

    /// Selection lives in whichever view the user is actually working in.
    var selectedItems: [ShelfItem] {
        if shelf.isExpanded, let panel = detailPanel, panel.parent != nil {
            return panel.itemsView.selectedItems
        }
        return itemsView.selectedItems
    }

    // MARK: - Actions from chrome

    @objc private func didSelectPilePill() {
        togglePresentation()
    }

    @objc private func didSelectBarButton() {
        let menu = actionMenu(for: selectedItems)
        let point = NSPoint(x: barButton.bounds.minX, y: barButton.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: point, in: barButton)
    }

    @objc private func didSelectPinButton() {
        shelf.pinned.toggle()
        applyDocumentState()
        ShelfStore.shared.notifyChange()
    }

    @objc private func didSelectCloseButton() {
        closeShelf()
    }

    /// Renames the shelf. `nil` or empty restores the automatic label.
    func rename(to newTitle: String?) {
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        shelf.title = (trimmed?.isEmpty ?? true) ? nil : trimmed
        refresh()
    }

    // MARK: - Hover
    //
    // Hover must never change the window's geometry. An earlier build expanded
    // a parked shelf on mouse-enter and re-collapsed it on mouse-exit, which
    // oscillated: expanding moved the frame out from under the pointer, firing
    // another exit. The only hover-driven movement left is the docked-shelf
    // peek, which the user opts into explicitly by docking.

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if shelf.dockedEdge != nil { revealDocked(true) }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if shelf.dockedEdge != nil { revealDocked(false) }
    }

    // MARK: - Presentation: pile card vs. full list
    //
    // A shelf normally shows its contents as a fanned pile with an
    // "N Files ⌄" pill, the way Dropover does. The pill — and only the pill or
    // the action menu — expands it to the grid/list. Size changes are therefore
    // always a direct response to a click.

    private static let pileCardSize = NSSize(width: 184, height: 194)
    private static let parkedMargin: CGFloat = 12

    /// Deliberately unhurried, with a long decelerating tail so the move reads
    /// as deliberate rather than snapping.
    private static let moveDuration: TimeInterval = 0.52
    private static let resizeDuration: TimeInterval = 0.36
    private static var easing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    }

    var isShelfParked: Bool { shelf.isParked }

    /// Called by the pile's "N Files" pill and by the action menu.
    func togglePresentation() {
        setExpanded(!shelf.isExpanded)
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard shelf.isExpanded != expanded else { return }
        shelf.isExpanded = expanded
        applyChrome()
        ShelfStore.shared.notifyChange()
    }

    // MARK: Detail dropdown

    private func showDetailPanel() {
        guard let window else { return }

        let panel = detailPanel ?? ShelfDetailPanel(controller: self)
        detailPanel = panel
        panel.refresh()

        let size = panel.fittingSize()

        let finalFrame = detailFrame(for: size)
        if panel.parent == nil {
            // Start tucked up behind the card and slightly narrow, then drop
            // into place — the dropdown should feel like it unfolds.
            var start = finalFrame
            start.origin.y += 14
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = Self.easing
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func hideDetailPanel() {
        guard let panel = detailPanel else { return }
        var retreat = panel.frame
        retreat.origin.y += 12
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(retreat, display: true)
        } completionHandler: { [weak self] in
            guard let self, let window = self.window else { return }
            window.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    /// Positions the dropdown under the card, nudged back on screen if the
    /// card sits near an edge (which it does whenever it is parked).
    private func detailFrame(for size: NSSize) -> NSRect {
        guard let window else { return NSRect(origin: .zero, size: size) }
        let card = window.frame
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        var origin = NSPoint(x: card.minX, y: card.minY - Self.detailGap - size.height)
        if origin.x + size.width > visible.maxX - 8 {
            origin.x = max(visible.minX + 8, card.maxX - size.width)
        }
        if origin.x < visible.minX + 8 { origin.x = visible.minX + 8 }
        // No room below: hang it above the card instead.
        if origin.y < visible.minY + 8 {
            origin.y = card.maxY + Self.detailGap
        }
        return NSRect(origin: origin, size: size)
    }

    /// Keeps the dropdown glued to the card after a move, resize or content
    /// change. Child windows follow the parent automatically, but the fitted
    /// height and the on-screen nudging still have to be recomputed.
    private func repositionDetailPanel() {
        guard let panel = detailPanel, panel.parent != nil else { return }
        panel.refresh()
        panel.setFrame(detailFrame(for: panel.fittingSize()), display: true)
    }

    /// Shows or hides the chrome that only the expanded presentation has.
    private func applyChrome() {
        let expanded = shelf.isExpanded
        // The card never changes: only the dropdown comes and goes.
        expanded ? showDetailPanel() : hideDetailPanel()
    }

    // MARK: - Parking (retract)
    //
    // `preferences.retract-windows-popover.body`: "After the initial file drop,
    // the shelf moves aside to stay out of the way." Parking only *moves* the
    // shelf; it does not change its presentation.

    func toggleRetracted() {
        setParked(!shelf.isParked)
    }

    func setRetracted(_ parked: Bool, animated: Bool = true) {
        setParked(parked, animated: animated)
    }

    func setParked(_ parked: Bool, animated: Bool = true) {
        guard shelf.isParked != parked, let window, shelf.dockedEdge == nil else { return }
        if parked { restingTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY) }
        shelf.isParked = parked
        setFrame(frameForCurrentState(), animated: animated, duration: Self.moveDuration)
        ShelfStore.shared.notifyChange()
    }

    /// The frame the window should have for its current presentation and
    /// parked state. The top-left corner is the anchor, so growing or shrinking
    /// never shifts the shelf out from under the pointer.
    private func frameForCurrentState() -> NSRect {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        let size = Self.pileCardSize // the card is a fixed-size object

        if shelf.isParked {
            let parked = ShelfStore.shared.controllers.filter { $0.isShelfParked }
            let slot = parked.firstIndex { $0 === self } ?? 0
            let offset = CGFloat(slot) * (Self.pileCardSize.height + 10)
            var frame = NSRect(x: visible.maxX - size.width - Self.parkedMargin,
                               y: visible.maxY - size.height - Self.parkedMargin - offset,
                               width: size.width,
                               height: size.height)
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            return frame
        }

        let frame = NSRect(x: restingTopLeft.x,
                           y: restingTopLeft.y - size.height,
                           width: size.width,
                           height: size.height)
        return ShelfStore.clamp(frame,
                                toScreenContaining: NSPoint(x: frame.midX, y: frame.midY))
    }

    // MARK: - Docking

    func dock(to edge: ShelfEdge, animated: Bool = true) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if shelf.dockedEdge == nil { undockedFrame = window.frame }
        shelf.dockedEdge = edge
        isDockRevealed = false

        let visible = screen.visibleFrame
        var frame = window.frame
        switch edge {
        case .left: frame.origin.x = visible.minX - frame.width + Self.dockTabWidth
        case .right: frame.origin.x = visible.maxX - Self.dockTabWidth
        }
        setFrame(frame, animated: animated)
        ShelfStore.shared.notifyChange()
    }

    func undock() {
        guard let window, shelf.dockedEdge != nil else { return }
        shelf.dockedEdge = nil
        isDockRevealed = false
        let target = undockedFrame ?? window.frame
        undockedFrame = nil
        setFrame(target, animated: true)
        ShelfStore.shared.notifyChange()
    }

    private func revealDocked(_ reveal: Bool) {
        guard let window,
              let edge = shelf.dockedEdge,
              let screen = window.screen ?? NSScreen.main,
              reveal != isDockRevealed else { return }
        isDockRevealed = reveal

        let visible = screen.visibleFrame
        var frame = window.frame
        switch (edge, reveal) {
        case (.left, true): frame.origin.x = visible.minX
        case (.left, false): frame.origin.x = visible.minX - frame.width + Self.dockTabWidth
        case (.right, true): frame.origin.x = visible.maxX - frame.width
        case (.right, false): frame.origin.x = visible.maxX - Self.dockTabWidth
        }
        setFrame(frame, animated: true)
    }

    private func setFrame(_ frame: NSRect,
                          animated: Bool,
                          duration: TimeInterval = ShelfWindowController.moveDuration,
                          completion: (() -> Void)? = nil) {
        guard let window else { return }
        guard animated else {
            window.setFrame(frame, display: true)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Self.easing
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            completion?()
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard shelf.dockedEdge == nil else { return }
        // A shelf the user drags by hand is no longer parked.
        if shelf.isParked, NSEvent.pressedMouseButtons & 1 != 0 {
            shelf.isParked = false
        }
        repositionDetailPanel()
        guard !shelf.isParked else { return }
        if let window {
            restingTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        }
        scheduleSnap()
    }

    func windowDidResize(_ notification: Notification) {
        if let window, shelf.isExpanded, !shelf.isParked, shelf.dockedEdge == nil {
            shelf.frame.size = window.frame.size
            restingTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        }
        itemsView.invalidateLayout()
        syncDocumentFrame()
    }

    func windowWillClose(_ notification: Notification) {
        ShelfStore.shared.didClose(self)
    }

    /// `preferences.snap-windows-checkbox` — snap on release, and let ⌘ defeat it.
    private func scheduleSnap() {
        moveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Still dragging? Wait for the release.
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.scheduleSnap()
                return
            }
            self.snapIfNeeded()
            self.syncDocumentFrame()
        }
        moveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func snapIfNeeded() {
        // A parked shelf sits at a deliberate margin from the corner; snapping
        // would pull it flush and eat that margin.
        guard !shelf.isParked, shelf.dockedEdge == nil,
              Preferences.shared.snapWindows,
              !NSEvent.modifierFlags.contains(.command),
              let window,
              let screen = window.screen else { return }

        var frame = window.frame
        let d = Self.snapDistance
        var candidatesX: [CGFloat] = []
        var candidatesY: [CGFloat] = []

        let visible = screen.visibleFrame
        candidatesX += [visible.minX, visible.maxX - frame.width]
        candidatesY += [visible.minY, visible.maxY - frame.height]

        for other in ShelfStore.shared.controllers where other !== self {
            guard let otherFrame = other.window?.frame else { continue }
            candidatesX += [otherFrame.minX, otherFrame.maxX, otherFrame.maxX,
                            otherFrame.minX - frame.width]
            candidatesY += [otherFrame.minY, otherFrame.maxY,
                            otherFrame.minY - frame.height, otherFrame.maxY]
        }

        if let x = candidatesX.min(by: { abs($0 - frame.minX) < abs($1 - frame.minX) }),
           abs(x - frame.minX) <= d {
            frame.origin.x = x
        }
        if let y = candidatesY.min(by: { abs($0 - frame.minY) < abs($1 - frame.minY) }),
           abs(y - frame.minY) <= d {
            frame.origin.y = y
        }

        if frame != window.frame {
            setFrame(frame, animated: true)
        }
    }

    // MARK: - Opening items

    func open(items: [ShelfItem]) {
        for item in items {
            switch item.payload {
            case .file(let url):
                NSWorkspace.shared.open(url)
            case .webURL(let url):
                NSWorkspace.shared.open(url)
            default:
                if let url = item.fileURL() { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: - Drag-out writers

    /// The pasteboard writer for one item.
    ///
    /// Real files hand over their URL so the destination performs the actual
    /// move or copy. Synthesised payloads use a file promise (images) or plain
    /// pasteboard data (text), so text lands as text in editors.
    func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting? {
        switch item.payload {
        case .file(let url):
            return url as NSURL
        case .webURL(let url):
            return url as NSURL
        case .plainText(let text):
            let pbItem = NSPasteboardItem()
            pbItem.setString(text, forType: .string)
            return pbItem
        case .richText(let data):
            let pbItem = NSPasteboardItem()
            pbItem.setData(data, forType: .rtf)
            if let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
                pbItem.setString(attributed.string, forType: .string)
            }
            return pbItem
        case .image(let data):
            let provider = ShelfFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
            provider.userInfo = item.id.uuidString
            provider.extraTypes = [.png: data]
            return provider
        }
    }

    // MARK: - Quick Look

    func showQuickLook() {
        let items = selectedItems.isEmpty ? shelf.items : selectedItems
        let urls = items.compactMap { $0.fileURL() }
        guard !urls.isEmpty else { return }
        quickLookURLs = urls

        NSApp.activate(ignoringOtherApps: true)
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    // MARK: - Shelf keyboard shortcuts
    //
    // `keyboard-action-settings.section.shelf.description` says shelf
    // shortcuts are live while the cursor hovers the shelf. Two paths feed
    // this: the panel's own key handling when the app is active, and a global
    // monitor gated on hover (see AppDelegate).

    @discardableResult
    func handleShelfKey(_ event: NSEvent) -> Bool {
        // Never swallow keys while a text field is being edited.
        if window?.firstResponder is NSTextView { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command {
            switch chars {
            case "w": closeShelf(); return true
            case "a": itemsView.selectAllItems(); selectionDidChange(); return true
            case "c": copySelectionToClipboard(); return true
            case "v": pasteFromClipboard(); return true
            case "k": clear(); return true
            case "e": togglePresentation(); return true
            case "n":
                ShelfStore.shared.createShelf(at: NSEvent.mouseLocation,
                                              items: selectedItems)
                return true
            default: return false
            }
        }

        if flags == [.command, .shift], chars == "w" {
            ShelfStore.shared.closeAll()
            return true
        }

        if flags.isEmpty {
            switch event.keyCode {
            case 53: // escape
                closeShelf(); return true
            case 49: // space
                showQuickLook(); return true
            case 36: // return
                open(items: selectedItems); return true
            case 51, 117: // delete / forward delete
                let selected = selectedItems
                if !selected.isEmpty { remove(items: selected); return true }
                return false
            default: return false
            }
        }

        return false
    }

    func copySelectionToClipboard() {
        let items = selectedItems.isEmpty ? shelf.items : selectedItems
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let writers = items.compactMap { pasteboardWriter(for: $0) }
        pasteboard.writeObjects(writers)
    }

    func pasteFromClipboard() {
        add(items: ShelfItem.items(from: NSPasteboard.general))
    }
}

// MARK: - Quick Look data source

extension ShelfWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard quickLookURLs.indices.contains(index) else { return nil }
        return quickLookURLs[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 49 {
            panel.orderOut(nil)
            return true
        }
        return false
    }
}

// MARK: - File promises

/// `NSFilePromiseProvider` that can also carry plain pasteboard data, so an
/// image dropped into Finder becomes a real `.png` while an image dropped into
/// an editor still arrives as image data.
final class ShelfFilePromiseProvider: NSFilePromiseProvider {
    var extraTypes: [NSPasteboard.PasteboardType: Data] = [:]

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + Array(extraTypes.keys)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if let data = extraTypes[type] { return data }
        return super.pasteboardPropertyList(forType: type)
    }
}

extension ShelfWindowController: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ provider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        guard let id = provider.userInfo as? String,
              let item = shelf.items.first(where: { $0.id.uuidString == id }),
              let url = item.fileURL() else {
            return "Item"
        }
        return url.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let id = provider.userInfo as? String,
              let item = shelf.items.first(where: { $0.id.uuidString == id }),
              let source = item.fileURL() else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: source, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }
}
