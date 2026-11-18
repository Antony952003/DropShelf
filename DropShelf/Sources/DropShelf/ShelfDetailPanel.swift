import AppKit

/// The dropdown that appears *below* a shelf card listing its actual files.
///
/// Dropover keeps the pile card intact and attaches this as a separate panel
/// (visible on the left of the reference screenshot: gear · "1 Image · 357 KB" ·
/// grid/list toggle, then the file rows). Making it a real child window means
/// AppKit moves it with the card for free.
final class ShelfDetailPanel: NSPanel {

    private weak var shelfController: ShelfWindowController?

    private let root = ShelfDetailRootView(frame: .zero)
    private let effectView = ShelfBackgroundView()
    private let gearButton = CircleGlyphButton(symbol: "gearshape",
                                               tooltip: "Open shelf preferences",
                                               diameter: 22, pointSize: 11)
    private let countLabel = NSTextField(labelWithString: "")
    private let segmentedControl = NSSegmentedControl()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    let itemsView = ShelfItemsView(frame: .zero)

    static let width: CGFloat = 340
    private static let headerHeight: CGFloat = 34
    private static let maxContentHeight: CGFloat = 260
    private static let minContentHeight: CGFloat = 76
    static let cornerRadius: CGFloat = 12

    init(controller: ShelfWindowController) {
        self.shelfController = controller
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        // Never move with a background drag — the card owns positioning.
        isMovableByWindowBackground = false
        animationBehavior = .none

        build(controller: controller)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: Construction

    private func build(controller: ShelfWindowController) {
        root.controller = controller
        root.frame = NSRect(origin: .zero, size: frame.size)
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.cornerRadius = Self.cornerRadius
        root.layer?.masksToBounds = true
        contentView = root

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Self.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(effectView)

        gearButton.target = self
        gearButton.action = #selector(didSelectGear)
        root.addSubview(gearButton)

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(countLabel)

        segmentedControl.segmentStyle = .texturedRounded
        segmentedControl.segmentCount = 2
        segmentedControl.setImage(NSImage(systemSymbolName: "square.grid.2x2",
                                          accessibilityDescription: "Show files as icons"),
                                  forSegment: 0)
        segmentedControl.setImage(NSImage(systemSymbolName: "list.bullet",
                                          accessibilityDescription: "Show files in a list"),
                                  forSegment: 1)
        segmentedControl.target = self
        segmentedControl.action = #selector(didChangeLayout)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(segmentedControl)

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separator)

        itemsView.controller = controller
        itemsView.isCollapsed = false
        scrollView.documentView = itemsView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(clipViewFrameChanged),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: root.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            gearButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            gearButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 7),
            gearButton.widthAnchor.constraint(equalToConstant: 22),
            gearButton.heightAnchor.constraint(equalToConstant: 22),

            segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            segmentedControl.centerYAnchor.constraint(equalTo: gearButton.centerYAnchor),

            countLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: gearButton.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: gearButton.trailingAnchor,
                                                constant: 8),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: segmentedControl.leadingAnchor,
                                                 constant: -8),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.headerHeight),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Actions

    @objc private func didSelectGear() {
        SettingsWindowController.shared.show()
    }

    @objc private func didChangeLayout() {
        shelfController?.setLayout(segmentedControl.selectedSegment == 0 ? .grid : .list)
    }

    @objc private func clipViewFrameChanged() {
        itemsView.invalidateLayout()
    }

    // MARK: Content

    /// Pulls fresh state from the shelf and resizes to fit.
    func refresh() {
        guard let shelf = shelfController?.shelf else { return }
        segmentedControl.selectedSegment = shelf.layout == .grid ? 0 : 1
        itemsView.layout = shelf.layout
        itemsView.reload()
        updateCountLabel()
    }

    func updateCountLabel() {
        guard let shelf = shelfController?.shelf else { return }
        let selected = itemsView.selectedItems
        let shown = selected.isEmpty ? shelf.items : selected
        let bytes = shown.compactMap(\.byteSize).reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)

        if !selected.isEmpty {
            countLabel.stringValue = "Selected: \(selected.count) · \(size)"
        } else if let title = shelf.title, !title.isEmpty {
            countLabel.stringValue = "\(title) · \(size)"
        } else if shelf.items.isEmpty {
            countLabel.stringValue = "No content"
        } else {
            let noun = shelf.items.count == 1 ? "1 Item" : "\(shelf.items.count) Items"
            countLabel.stringValue = "\(noun) · \(size)"
        }
    }

    /// Height that fits the current contents, bounded.
    func fittingSize() -> NSSize {
        let content = itemsView.requiredHeight(forWidth: Self.width)
        let bounded = min(max(content, Self.minContentHeight), Self.maxContentHeight)
        return NSSize(width: Self.width, height: Self.headerHeight + 1 + bounded)
    }
}

/// Root view of the detail panel: accepts drops and moves the *card* when
/// dragged, so the pair behaves as one object.
final class ShelfDetailRootView: NSView {

    weak var controller: ShelfWindowController?

    private var isDropTargeted = false {
        didSet { if oldValue != isDropTargeted { needsDisplay = true } }
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes(ShelfItem.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = ShelfDetailPanel.cornerRadius
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius - 0.5, yRadius: radius - 0.5)
        edge.lineWidth = 1
        NSColor.separatorColor.setStroke()
        edge.stroke()

        guard isDropTargeted else { return }
        let accent = controller?.shelf.color ?? .controlAccentColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                xRadius: radius - 2, yRadius: radius - 2)
        accent.withAlphaComponent(0.12).setFill()
        path.fill()
        path.lineWidth = 2.5
        accent.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        // Dragging the dropdown drags the whole shelf.
        controller?.window?.performDrag(with: event)
    }

    // MARK: Dragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTargeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { isDropTargeted = false }

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
}
