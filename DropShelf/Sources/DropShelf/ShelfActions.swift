import AppKit
import UniformTypeIdentifiers

/// Dispatcher for closure-backed menu items. Lives as a singleton so menu
/// items never have to retain themselves as their own target.
final class MenuActionDispatcher: NSObject {
    static let shared = MenuActionDispatcher()

    @objc func perform(_ sender: NSMenuItem) {
        (sender as? BlockMenuItem)?.invoke()
    }
}

final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String? = nil, keyEquivalent: String = "",
         enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title,
                   action: #selector(MenuActionDispatcher.perform(_:)),
                   keyEquivalent: keyEquivalent)
        target = MenuActionDispatcher.shared
        isEnabled = enabled
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    func invoke() { handler() }
}

// MARK: - The shelf action menu
//
// Item set mirrors Dropover's `action.*` strings (ANALYSIS.md §4). Cloud-link
// actions are the deliberate omission; `cloudProviderMenuItems` is where they
// would attach.

extension ShelfWindowController {

    func actionMenu(for selection: [ShelfItem]) -> NSMenu {
        let menu = NSMenu()
        let targets = selection.isEmpty ? shelf.items : selection
        let hasTargets = !targets.isEmpty
        let fileURLs = targets.compactMap { item -> URL? in
            if case .file(let url) = item.payload { return url }
            return nil
        }

        if hasTargets {
            // Match the pile pill's wording: "2 Images", not "2 Items".
            let noun = targets.count == 1 ? targets[0].displayName : pillTitle()

            menu.addItem(BlockMenuItem(title: "Open", symbol: "arrow.up.forward.app") { [weak self] in
                self?.open(items: targets)
            })

            if let openWith = openWithMenu(for: fileURLs) {
                let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                item.submenu = openWith
                menu.addItem(item)
            }

            if !fileURLs.isEmpty {
                menu.addItem(BlockMenuItem(title: "Reveal in Finder", symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
                })
            }

            menu.addItem(BlockMenuItem(title: "Quick Look", symbol: "eye", keyEquivalent: " ") { [weak self] in
                self?.showQuickLook()
            })

            menu.addItem(.separator())

            menu.addItem(BlockMenuItem(title: "Copy \(Self.truncate(noun))",
                                       symbol: "doc.on.doc") { [weak self] in
                self?.copyTargets(targets)
            })
        }

        menu.addItem(BlockMenuItem(title: "Add From Clipboard", symbol: "clipboard") { [weak self] in
            self?.pasteFromClipboard()
        })

        if hasTargets {
            menu.addItem(.separator())

            menu.addItem(BlockMenuItem(title: "Compress", symbol: "archivebox") { [weak self] in
                self?.compress(items: targets)
            })

            menu.addItem(BlockMenuItem(title: "Share…", symbol: "square.and.arrow.up") { [weak self] in
                self?.share(items: targets)
            })

            for item in cloudProviderMenuItems(for: targets) {
                menu.addItem(item)
            }

            menu.addItem(.separator())

            menu.addItem(BlockMenuItem(title: "Move to New Shelf", symbol: "arrow.right.square") { [weak self] in
                guard let self else { return }
                ShelfStore.shared.createShelf(at: NSEvent.mouseLocation, items: targets)
                self.remove(items: targets)
            })

            menu.addItem(BlockMenuItem(title: "Show in New Shelf", symbol: "plus.square.on.square") {
                ShelfStore.shared.createShelf(at: NSEvent.mouseLocation, items: targets)
            })
        }

        menu.addItem(.separator())

        // Shelf-level items
        let dockMenu = NSMenu()
        if shelf.dockedEdge != nil {
            dockMenu.addItem(BlockMenuItem(title: "Undock") { [weak self] in self?.undock() })
        }
        dockMenu.addItem(BlockMenuItem(title: "Dock to Left Edge") { [weak self] in
            self?.dock(to: .left)
        })
        dockMenu.addItem(BlockMenuItem(title: "Dock to Right Edge") { [weak self] in
            self?.dock(to: .right)
        })
        let dockItem = NSMenuItem(title: "Dock to Edge", action: nil, keyEquivalent: "")
        dockItem.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: nil)
        dockItem.submenu = dockMenu
        menu.addItem(dockItem)

        menu.addItem(BlockMenuItem(title: shelf.isExpanded ? "Hide Files" : "Show Files",
                                   symbol: shelf.isExpanded ? "chevron.up" : "chevron.down",
                                   keyEquivalent: "e") { [weak self] in
            self?.togglePresentation()
        })

        menu.addItem(BlockMenuItem(title: "Rename Shelf…", symbol: "pencil") { [weak self] in
            self?.promptForRename()
        })

        menu.addItem(BlockMenuItem(title: shelf.isParked ? "Bring Back" : "Move Aside",
                                   symbol: shelf.isParked
                                       ? "arrow.down.left.circle"
                                       : "arrow.up.right.circle") { [weak self] in
            self?.toggleRetracted()
        })

        let layoutMenu = NSMenu()
        let gridItem = BlockMenuItem(title: "Icons") { [weak self] in self?.setLayout(.grid) }
        gridItem.state = shelf.layout == .grid ? .on : .off
        let listItem = BlockMenuItem(title: "List") { [weak self] in self?.setLayout(.list) }
        listItem.state = shelf.layout == .list ? .on : .off
        layoutMenu.addItem(gridItem)
        layoutMenu.addItem(listItem)
        let layoutItem = NSMenuItem(title: "View As", action: nil, keyEquivalent: "")
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)

        let pinItem = BlockMenuItem(title: shelf.pinned ? "Unpin Shelf" : "Pin Shelf",
                                    symbol: shelf.pinned ? "pin.slash" : "pin") { [weak self] in
            guard let self else { return }
            self.shelf.pinned.toggle()
            self.refresh()
        }
        menu.addItem(pinItem)

        menu.addItem(.separator())

        if !selection.isEmpty {
            menu.addItem(BlockMenuItem(title: "Remove From Shelf", symbol: "minus.circle") { [weak self] in
                self?.remove(items: selection)
            })
        }

        menu.addItem(BlockMenuItem(title: "Clear Shelf", symbol: "trash",
                                   enabled: !shelf.items.isEmpty) { [weak self] in
            self?.clear()
        })

        menu.addItem(BlockMenuItem(title: "Close", symbol: "xmark") { [weak self] in
            self?.closeShelf()
        })

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Settings…", symbol: "gearshape") {
            SettingsWindowController.shared.show()
        })

        return menu
    }

    /// Extension point for the cloud providers this rebuild does not ship
    /// (Dropover Cloud, S3, Dropbox, Google Drive, OneDrive, Imgur, iCloud).
    /// Returning `[]` keeps the menu honest rather than showing dead entries.
    private func cloudProviderMenuItems(for items: [ShelfItem]) -> [NSMenuItem] {
        []
    }

    private func openWithMenu(for urls: [URL]) -> NSMenu? {
        guard let first = urls.first else { return nil }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        guard !apps.isEmpty else { return nil }

        let menu = NSMenu()
        // Two installs of the same app (or one registered twice) otherwise show
        // up as duplicate rows — collapse by bundle identifier.
        var seen = Set<String>()
        let unique = apps.filter { url in
            let key = Bundle(url: url)?.bundleIdentifier ?? url.standardizedFileURL.path
            return seen.insert(key).inserted
        }

        for app in unique.prefix(12) {
            let name = FileManager.default.displayName(atPath: app.path)
            let item = BlockMenuItem(title: name) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config)
            }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }

    private func copyTargets(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.compactMap { pasteboardWriter(for: $0) })
    }

    private func share(items: [ShelfItem]) {
        let urls = items.compactMap { $0.fileURL() }
        guard !urls.isEmpty, let anchor = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 30,
                                       width: 1, height: 1),
                    of: anchor,
                    preferredEdge: .minY)
    }

    /// `action.compress.*` — zips the targets with `ditto` and puts the archive
    /// back on the shelf.
    private func compress(items: [ShelfItem]) {
        let urls = items.compactMap { $0.fileURL() }
        guard !urls.isEmpty else { return }

        let name = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : "Archive"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropShelf-Archives/\(UUID().uuidString)", isDirectory: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let archive = dir.appendingPathComponent("\(name).zip")

                // ditto handles multiple inputs by staging them in a folder first.
                let stage = dir.appendingPathComponent("stage", isDirectory: true)
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                for url in urls {
                    let destination = stage.appendingPathComponent(url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: url, to: destination)
                    }
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                     stage.path, archive.path]
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
                DispatchQueue.main.async {
                    self?.add(items: [ShelfItem(payload: .file(archive))])
                }
            } catch {
                DispatchQueue.main.async {
                    self?.presentError(title: "Compression failed",
                                       message: error.localizedDescription)
                }
            }
        }
    }

    /// The title field moved into the dropdown's header, so renaming is a
    /// prompt rather than inline editing.
    func promptForRename() {
        let alert = NSAlert()
        alert.messageText = "Rename Shelf"
        alert.informativeText = "Leave this empty to go back to the automatic label."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = shelf.title ?? ""
        field.placeholderString = shelf.autoTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        rename(to: field.stringValue)
    }

    func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func truncate(_ string: String, limit: Int = 28) -> String {
        string.count <= limit ? string : String(string.prefix(limit - 1)) + "…"
    }
}
