import AppKit

enum ShelfEdge: String, Codable {
    case left, right
}

/// The persisted state of one shelf.
final class ShelfDocument: Codable {
    let id: UUID
    /// `nil` means "unnamed" — the shelf shows its item count instead.
    var title: String?
    var items: [ShelfItem]
    var layout: ShelfLayout
    var colorIndex: Int
    var pinned: Bool
    var frame: CGRect
    var dockedEdge: ShelfEdge?
    var createdAt: Date
    var hasReceivedDrop: Bool

    /// `false` (the default) shows the fanned pile card; `true` shows the full
    /// grid/list. Toggled only by the user — never by hovering.
    var isExpanded: Bool

    /// Parked in the screen corner, out of the way.
    var isParked: Bool

    init(items: [ShelfItem] = [], frame: CGRect, colorIndex: Int) {
        self.id = UUID()
        self.title = nil
        self.items = items
        self.layout = Preferences.shared.defaultLayout
        self.colorIndex = colorIndex
        self.pinned = false
        self.frame = frame
        self.dockedEdge = nil
        self.createdAt = Date()
        self.hasReceivedDrop = !items.isEmpty
        self.isExpanded = false
        self.isParked = false
    }

    // Hand-written so that state files written by an earlier build still
    // decode: new keys fall back to their defaults instead of throwing.
    private enum CodingKeys: String, CodingKey {
        case id, title, items, layout, colorIndex, pinned, frame
        case dockedEdge, createdAt, hasReceivedDrop, isExpanded, isParked
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        items = try c.decodeIfPresent([ShelfItem].self, forKey: .items) ?? []
        layout = try c.decodeIfPresent(ShelfLayout.self, forKey: .layout) ?? .grid
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
            ?? CGRect(x: 0, y: 0, width: 320, height: 240)
        dockedEdge = try c.decodeIfPresent(ShelfEdge.self, forKey: .dockedEdge)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        hasReceivedDrop = try c.decodeIfPresent(Bool.self, forKey: .hasReceivedDrop) ?? !items.isEmpty
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        isParked = try c.decodeIfPresent(Bool.self, forKey: .isParked) ?? false
    }

    /// What an unnamed shelf shows. Never stored in `title` — it is the text
    /// field's *placeholder*, so renaming starts from an empty field and
    /// clearing the field restores "unnamed" rather than baking in a count.
    var autoTitle: String {
        if items.isEmpty { return "Shelf" }
        return items.count == 1 ? "1 item" : "\(items.count) items"
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return autoTitle
    }

    var color: NSColor { ShelfPalette.color(at: colorIndex) }

    /// Items that still point at something real.
    func pruneUnresolvable() {
        items.removeAll { !$0.isResolvable }
    }
}

/// Owns every live shelf window plus the recent/pinned lists behind the
/// menu-bar menu (`menu.item.recent-windows`, `menu.item.pinned-windows`).
final class ShelfStore {
    static let shared = ShelfStore()

    private(set) var controllers: [ShelfWindowController] = []
    private(set) var recentlyClosed: [ShelfDocument] = []

    private var colorCursor = 0
    private let maxRecent = 20
    private var saveWorkItem: DispatchWorkItem?

    static let didChange = Notification.Name("DropShelf.shelvesDidChange")

    private init() {}

    // MARK: - Creating

    private static let defaultSize = CGSize(width: 320, height: 240)

    /// Creates a shelf centred on `point` (screen coordinates), clamped so it
    /// stays fully on its screen.
    @discardableResult
    func createShelf(at point: CGPoint, items: [ShelfItem] = []) -> ShelfWindowController {
        let size = Self.defaultSize
        var frame = CGRect(x: point.x - size.width / 2,
                           y: point.y - size.height / 2,
                           width: size.width,
                           height: size.height)
        frame = Self.place(frame, near: point)

        let shelf = ShelfDocument(items: items, frame: frame, colorIndex: colorCursor)
        colorCursor += 1

        let controller = ShelfWindowController(shelf: shelf)
        controller.parkAfterShowing = !items.isEmpty
        controllers.append(controller)
        controller.showShelf()
        notifyChange()
        return controller
    }

    @discardableResult
    func reopen(_ shelf: ShelfDocument) -> ShelfWindowController {
        shelf.pruneUnresolvable()
        shelf.frame = Self.clamp(shelf.frame, toScreenContaining: CGPoint(x: shelf.frame.midX,
                                                                                y: shelf.frame.midY))
        let controller = ShelfWindowController(shelf: shelf)
        controllers.append(controller)
        controller.showShelf()
        recentlyClosed.removeAll { $0.id == shelf.id }
        notifyChange()
        return controller
    }

    /// Two shelves summoned without moving the mouse would land exactly on top
    /// of each other, so step away until the spot is free.
    ///
    /// The step has to survive clamping: near the bottom of the screen a
    /// down-right cascade is pinned by `visibleFrame`, so fall back to
    /// up-right.
    private static func place(_ frame: CGRect, near point: CGPoint) -> CGRect {
        let start = clamp(frame, toScreenContaining: point)
        let steps = [CGSize(width: 24, height: -24), CGSize(width: 24, height: 24)]

        for step in steps {
            var candidate = start
            for _ in 0..<12 {
                if !isOccupied(candidate) { return candidate }
                var moved = candidate
                moved.origin.x += step.width
                moved.origin.y += step.height
                let clamped = clamp(moved, toScreenContaining: point)
                if clamped == candidate { break } // pinned; try the other direction
                candidate = clamped
            }
        }
        return start
    }

    private static func isOccupied(_ frame: CGRect) -> Bool {
        ShelfStore.shared.controllers.contains { controller in
            guard let other = controller.window?.frame else { return false }
            return abs(other.minX - frame.minX) < 10 && abs(other.minY - frame.minY) < 10
        }
    }

    static func clamp(_ frame: CGRect, toScreenContaining point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }
        var f = frame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }

    // MARK: - Lookup

    var frontmostShelf: ShelfWindowController? {
        if let key = controllers.first(where: { $0.window?.isKeyWindow == true }) { return key }
        return controllers.last
    }

    var hoveredShelf: ShelfWindowController? {
        let mouse = NSEvent.mouseLocation
        return controllers.first { $0.window?.frame.contains(mouse) == true }
    }

    func shelf(withID id: UUID) -> ShelfWindowController? {
        controllers.first { $0.shelf.id == id }
    }

    var pinnedDocuments: [ShelfDocument] {
        controllers.map(\.shelf).filter(\.pinned)
    }

    // MARK: - Closing

    func didClose(_ controller: ShelfWindowController) {
        controllers.removeAll { $0 === controller }
        let shelf = controller.shelf
        if !shelf.items.isEmpty {
            recentlyClosed.removeAll { $0.id == shelf.id }
            recentlyClosed.insert(shelf, at: 0)
            if recentlyClosed.count > maxRecent {
                recentlyClosed.removeLast(recentlyClosed.count - maxRecent)
            }
        }
        notifyChange()
    }

    func closeAll() {
        for controller in controllers.reversed() {
            controller.closeShelf()
        }
    }

    func reopenLastClosed() {
        guard let shelf = recentlyClosed.first else { return }
        reopen(shelf)
    }

    func removeRecent(_ shelf: ShelfDocument) {
        recentlyClosed.removeAll { $0.id == shelf.id }
        notifyChange()
    }

    func clearRecents() {
        recentlyClosed.removeAll()
        notifyChange()
    }

    // MARK: - Bulk shelf commands

    func toggleDockingForAllShelves() {
        let anyUndocked = controllers.contains { $0.shelf.dockedEdge == nil }
        for controller in controllers {
            if anyUndocked {
                if controller.shelf.dockedEdge == nil { controller.dock(to: .right) }
            } else {
                controller.undock()
            }
        }
    }

    // MARK: - Change notification & persistence

    func notifyChange() {
        NotificationCenter.default.post(name: ShelfStore.didChange, object: nil)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private struct PersistedState: Codable {
        var open: [ShelfDocument]
        var recent: [ShelfDocument]
        var colorCursor: Int
    }

    private var stateURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("DropShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shelves.json")
    }

    func save() {
        guard let url = stateURL else { return }
        for controller in controllers { controller.syncDocumentFrame() }
        let state = PersistedState(open: controllers.map(\.shelf),
                                   recent: recentlyClosed,
                                   colorCursor: colorCursor)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            NSLog("DropShelf: saving shelves failed: \(error.localizedDescription)")
        }
    }

    /// Restores pinned shelves and the recent list. Unpinned shelves are not
    /// reopened on launch — they move to "Recent Shelves" instead.
    func restore() {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }

        colorCursor = state.colorCursor
        recentlyClosed = state.recent

        for shelf in state.open {
            shelf.pruneUnresolvable()
            if shelf.pinned {
                reopen(shelf)
            } else if !shelf.items.isEmpty {
                recentlyClosed.append(shelf)
            }
        }
        if recentlyClosed.count > maxRecent {
            recentlyClosed.removeLast(recentlyClosed.count - maxRecent)
        }
        notifyChange()
    }
}
