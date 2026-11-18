import AppKit

/// `LSUIElement` agent app: status item, global activation, and the menu-bar
/// menu that mirrors Dropover's (`menu.item.*` in ANALYSIS.md §4).
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self

        applyActivationPolicy()
        rebuildStatusItem()

        DragActivationMonitor.shared.onActivate = { point in
            ShelfStore.shared.createShelf(at: point)
        }
        DragActivationMonitor.shared.onDragStateChange = { active in
            NotchDropController.shared.setDragActive(active)
        }
        DragActivationMonitor.shared.start()

        HotKeyCenter.shared.applyPreferences()
        HoverShortcutTap.shared.start()

        ScreenshotWatcher.shared.start()
        ShelfStore.shared.restore()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(preferencesDidChange),
                                               name: Preferences.didChange,
                                               object: nil)

        // Give the user a chance to grant Accessibility on first run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AccessibilityGate.warnIfNeeded()
            if AccessibilityGate.isTrusted { HoverShortcutTap.shared.start() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShelfStore.shared.save()
        DragActivationMonitor.shared.stop()
        HoverShortcutTap.shared.stop()
        HotKeyCenter.shared.unregisterAll()
        ScreenshotWatcher.shared.stop()
    }

    /// Agent app: closing windows must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon (when `Show in Dock` is on) opens a shelf.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if ShelfStore.shared.controllers.isEmpty {
            ShelfStore.shared.createShelf(at: NSEvent.mouseLocation)
        }
        return true
    }

    @objc private func preferencesDidChange() {
        applyActivationPolicy()
        rebuildStatusItem()
        HotKeyCenter.shared.applyPreferences()
        if Preferences.shared.hoverShortcuts {
            HoverShortcutTap.shared.start()
        } else {
            HoverShortcutTap.shared.stop()
        }
        if Preferences.shared.screenshotShelf {
            ScreenshotWatcher.shared.start()
        } else {
            ScreenshotWatcher.shared.stop()
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(Preferences.shared.showInDock ? .regular : .accessory)
    }

    // MARK: - Status item

    private func rebuildStatusItem() {
        guard Preferences.shared.showInMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }

        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.image = MenuBarIcon.image(for: Preferences.shared.menuBarIcon)
        item.button?.toolTip = "DropShelf"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = ShelfStore.shared
        let prefs = Preferences.shared

        func shortcutLabel(_ action: ShortcutAction) -> String {
            prefs.isShortcutEnabled(action) ? "  (\(prefs.shortcut(for: action).displayString))" : ""
        }

        menu.addItem(BlockMenuItem(title: "New Shelf" + shortcutLabel(.newShelf),
                                   symbol: "plus.rectangle.on.rectangle") {
            store.createShelf(at: NSEvent.mouseLocation)
        })

        menu.addItem(BlockMenuItem(title: "New Shelf From Clipboard" + shortcutLabel(.newClipboardShelf),
                                   symbol: "clipboard") {
            HotKeyCenter.perform(.newClipboardShelf)
        })

        menu.addItem(BlockMenuItem(title: "Reopen Last Closed Shelf" + shortcutLabel(.reopenLastClosedShelf),
                                   symbol: "arrow.uturn.backward",
                                   enabled: !store.recentlyClosed.isEmpty) {
            store.reopenLastClosed()
        })

        // Pinned shelves
        let pinned = store.pinnedDocuments
        if !pinned.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Pinned Shelves", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for shelf in pinned {
                menu.addItem(BlockMenuItem(title: "   " + shelf.displayTitle) {
                    store.shelf(withID: shelf.id)?.window?.orderFrontRegardless()
                })
            }
        }

        // Recent shelves
        menu.addItem(.separator())
        let recentItem = NSMenuItem(title: "Recent Shelves", action: nil, keyEquivalent: "")
        recentItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        let recentMenu = NSMenu()
        if store.recentlyClosed.isEmpty {
            let empty = NSMenuItem(title: "No recent shelves", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for shelf in store.recentlyClosed {
                let title = "\(shelf.displayTitle) — \(shelf.items.count) item"
                    + (shelf.items.count == 1 ? "" : "s")
                recentMenu.addItem(BlockMenuItem(title: title) {
                    // Hold ⌥ to remove a single entry instead of reopening it,
                    // matching `menu.item.recent-windows.clear-item-tip`.
                    if NSEvent.modifierFlags.contains(.option) {
                        store.removeRecent(shelf)
                    } else {
                        store.reopen(shelf)
                    }
                })
            }
            recentMenu.addItem(.separator())
            recentMenu.addItem(BlockMenuItem(title: "Clear Recent Shelves") {
                store.clearRecents()
            })
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Close All Shelves" + shortcutLabel(.closeAllShelves),
                                   symbol: "xmark.rectangle.portrait",
                                   enabled: !store.controllers.isEmpty) {
            store.closeAll()
        })

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Settings…", symbol: "gearshape", keyEquivalent: ",") {
            SettingsWindowController.shared.show()
        })
        menu.addItem(BlockMenuItem(title: "About DropShelf", symbol: "info.circle") {
            SettingsWindowController.shared.show(pane: .about)
        })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Quit DropShelf", symbol: "power", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    // MARK: - Services
    //
    // Counterpart to Dropover's `addToDropoverService` NSServices entry.

    @objc func addToShelfService(_ pasteboard: NSPasteboard,
                                 userData: String?,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let items = ShelfItem.items(from: pasteboard)
        guard !items.isEmpty else {
            error?.pointee = "Nothing on the pasteboard could be added to a shelf." as NSString
            return
        }
        if let shelf = ShelfStore.shared.frontmostShelf {
            shelf.add(items: items)
            shelf.window?.orderFrontRegardless()
        } else {
            ShelfStore.shared.createShelf(at: NSEvent.mouseLocation, items: items)
        }
    }

    // MARK: - URL scheme
    //
    // `settings` and `dock` exist as an escape hatch: on a Mac whose menu bar
    // is full the status item can end up hidden, and an LSUIElement app with no
    // Dock icon would otherwise be unreachable.

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "dropshelf" {
            switch url.host {
            case "new":
                ShelfStore.shared.createShelf(at: NSEvent.mouseLocation)
            case "clipboard":
                HotKeyCenter.perform(.newClipboardShelf)
            case "settings":
                SettingsWindowController.shared.show()
            case "dock":
                // Toggle the Dock icon, giving a permanently visible way in.
                Preferences.shared.showInDock.toggle()
                NSApp.activate(ignoringOtherApps: true)
            case "quit":
                NSApp.terminate(nil)
            default:
                break
            }
        }
    }
}
