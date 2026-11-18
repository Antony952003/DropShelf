import AppKit

enum SettingsPane: String, CaseIterable {
    case general, activation, shelf, shortcuts, applications, about

    var title: String {
        switch self {
        case .general: return "General"
        case .activation: return "Activation"
        case .shelf: return "Shelf"
        case .shortcuts: return "Shortcuts"
        case .applications: return "Ignored Apps"
        case .about: return "About"
        }
    }
}

// MARK: - Control plumbing

/// Retains a closure so plain AppKit controls can use closures for their action.
final class ActionTarget: NSObject {
    private let handler: (NSControl) -> Void

    init(_ handler: @escaping (NSControl) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// Shared builders for the settings rows.
class SettingsPaneController: NSViewController {

    private var targets: [ActionTarget] = []
    private var refreshers: [() -> Void] = []

    private let stack = NSStackView()

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = stack

        let container = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        view = container

        build()
    }

    /// Subclasses add their rows here.
    func build() {}

    func refresh() {
        for refresher in refreshers { refresher() }
    }

    // MARK: Row builders

    func add(_ view: NSView) {
        stack.addView(view, in: .leading)
    }

    func addHeader(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        add(label)
    }

    func addCaption(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 440
        add(label)
    }

    func addSeparator() {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 452).isActive = true
        add(box)
    }

    func addCheckbox(_ title: String,
                     get: @escaping () -> Bool,
                     set: @escaping (Bool) -> Void) -> NSButton {
        let target = ActionTarget { control in
            guard let button = control as? NSButton else { return }
            set(button.state == .on)
        }
        targets.append(target)

        let button = NSButton(checkboxWithTitle: title, target: target,
                              action: #selector(ActionTarget.fire(_:)))
        button.state = get() ? .on : .off
        refreshers.append { button.state = get() ? .on : .off }
        add(button)
        return button
    }

    func addPopUp<T: Equatable>(_ title: String,
                                options: [T],
                                titles: [String],
                                get: @escaping () -> T,
                                set: @escaping (T) -> Void) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: titles)
        if let index = options.firstIndex(of: get()) { popUp.selectItem(at: index) }

        let target = ActionTarget { control in
            guard let button = control as? NSPopUpButton else { return }
            let index = button.indexOfSelectedItem
            guard options.indices.contains(index) else { return }
            set(options[index])
        }
        targets.append(target)
        popUp.target = target
        popUp.action = #selector(ActionTarget.fire(_:))
        refreshers.append {
            if let index = options.firstIndex(of: get()) { popUp.selectItem(at: index) }
        }

        add(labeledRow(title, popUp))
        return popUp
    }

    func addButton(_ title: String, handler: @escaping () -> Void) -> NSButton {
        let target = ActionTarget { _ in handler() }
        targets.append(target)
        let button = NSButton(title: title, target: target, action: #selector(ActionTarget.fire(_:)))
        button.bezelStyle = .rounded
        add(button)
        return button
    }

    func labeledRow(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        return row
    }

    func track(_ refresher: @escaping () -> Void) {
        refreshers.append(refresher)
    }

    func retain(_ target: ActionTarget) {
        targets.append(target)
    }
}

// MARK: - General

final class GeneralPaneController: SettingsPaneController {
    override func build() {
        addHeader("Application")
        _ = addCheckbox("Launch at login",
                        get: { Preferences.shared.launchAtLogin },
                        set: { Preferences.shared.launchAtLogin = $0 })
        _ = addCheckbox("Show in menu bar",
                        get: { Preferences.shared.showInMenuBar },
                        set: { Preferences.shared.showInMenuBar = $0 })
        _ = addPopUp("Menu bar icon",
                     options: MenuBarIconStyle.allCases,
                     titles: MenuBarIconStyle.allCases.map(\.title),
                     get: { Preferences.shared.menuBarIcon },
                     set: { Preferences.shared.menuBarIcon = $0 })
        _ = addCheckbox("Show in Dock",
                        get: { Preferences.shared.showInDock },
                        set: { Preferences.shared.showInDock = $0 })

        addSeparator()
        addHeader("New shelves")
        _ = addPopUp("Open as",
                     options: [ShelfLayout.grid, ShelfLayout.list],
                     titles: ["Icons", "List"],
                     get: { Preferences.shared.defaultLayout },
                     set: { Preferences.shared.defaultLayout = $0 })
        _ = addCheckbox("Use color to differentiate shelves",
                        get: { Preferences.shared.useColorLabels },
                        set: { Preferences.shared.useColorLabels = $0 })
        addCaption("Each open shelf gets its own colour stripe for quick identification.")

        addSeparator()
        addHeader("Screenshots")
        _ = addCheckbox("Put new screenshots on a shelf",
                        get: { Preferences.shared.screenshotShelf },
                        set: {
                            Preferences.shared.screenshotShelf = $0
                            if $0 { ScreenshotWatcher.shared.restart() }
                            else { ScreenshotWatcher.shared.stop() }
                        })
        addCaption("Watches the folder macOS saves screenshots to — currently "
                   + ScreenshotWatcher.screenshotDirectory().path
                   + " — and groups shots taken close together onto one shelf.")

        addSeparator()
        _ = addButton("Restore Defaults") { [weak self] in
            Preferences.shared.restoreDefaults()
            HotKeyCenter.shared.applyPreferences()
            self?.refresh()
        }
    }
}

// MARK: - Activation

final class ActivationPaneController: SettingsPaneController {
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    override func build() {
        addCaption("Choose how to activate shelves using gestures, modifier keys, the notch, or keyboard shortcuts.")

        addSeparator()
        addHeader("Shake gesture")
        _ = addCheckbox("Activate with shake gesture",
                        get: { Preferences.shared.shakeEnabled },
                        set: { Preferences.shared.shakeEnabled = $0 })
        _ = addPopUp("Sensitivity",
                     options: ShakeSensitivity.allCases,
                     titles: ShakeSensitivity.allCases.map(\.title),
                     get: { Preferences.shared.shakeSensitivity },
                     set: { Preferences.shared.shakeSensitivity = $0 })
        addCaption("Shake the cursor while dragging.")

        addSeparator()
        addHeader("Modifier key")
        _ = addPopUp("Activate with",
                     options: ActivationModifier.allCases,
                     titles: ActivationModifier.allCases.map(\.title),
                     get: { Preferences.shared.activationModifier },
                     set: { Preferences.shared.activationModifier = $0 })
        addCaption("Hold a modifier key while dragging.")

        addSeparator()
        addHeader("Notch")
        _ = addCheckbox("Drop to notch",
                        get: { Preferences.shared.notchEnabled },
                        set: { Preferences.shared.notchEnabled = $0 })
        _ = addPopUp("Highlighting",
                     options: NotchHighlightMode.allCases,
                     titles: NotchHighlightMode.allCases.map(\.title),
                     get: { Preferences.shared.notchHighlight },
                     set: { Preferences.shared.notchHighlight = $0 })
        addCaption("On a Mac without a notch the drop target sits at the top centre of the screen.")

        addSeparator()
        addHeader("Permissions")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.preferredMaxLayoutWidth = 440
        add(statusLabel)
        _ = addButton("Open Accessibility Settings…") {
            AccessibilityGate.requestTrust()
            AccessibilityGate.openSystemSettings()
        }
        track { [weak self] in self?.updateStatus() }
        updateStatus()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateStatus()
    }

    private func updateStatus() {
        if AccessibilityGate.isTrusted {
            statusLabel.stringValue = "✓ Accessibility access granted — shake, modifier-key and hover shortcuts are available."
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "⚠︎ Accessibility access is required for shake, modifier-key and hover shortcuts. Keyboard shortcuts, the notch target and the menu bar work without it."
            statusLabel.textColor = .systemOrange
        }
    }
}

// MARK: - Shelf interaction

final class ShelfPaneController: SettingsPaneController {
    override func build() {
        addHeader("Dragging")
        _ = addCheckbox("Copy files instead of moving",
                        get: { Preferences.shared.copyInsteadOfMove },
                        set: { Preferences.shared.copyInsteadOfMove = $0 })
        addCaption("Dragged content is moved to the destination by default, unless the destination is on another volume.")
        _ = addCheckbox("Convert text to plain text",
                        get: { Preferences.shared.forcePlainText },
                        set: { Preferences.shared.forcePlainText = $0 })
        addCaption("Dragging text keeps its formatting by default.")
        _ = addCheckbox("Close shelf after dragging",
                        get: { Preferences.shared.closeAfterDrag },
                        set: { Preferences.shared.closeAfterDrag = $0 })

        addSeparator()
        addHeader("Placement")
        _ = addCheckbox("Snap into place",
                        get: { Preferences.shared.snapWindows },
                        set: { Preferences.shared.snapWindows = $0 })
        addCaption("Shelves snap and align after moving. Hold ⌘ while dragging to disable it.")
        _ = addCheckbox("Automatically retract",
                        get: { Preferences.shared.autoRetract },
                        set: { Preferences.shared.autoRetract = $0 })
        addCaption("After the first drop the shelf collapses to its title bar until you hover it.")
        _ = addCheckbox("Restrict to current Space",
                        get: { Preferences.shared.restrictToCurrentSpace },
                        set: { Preferences.shared.restrictToCurrentSpace = $0 })
        addCaption("Shelves appear in all Spaces by default.")
        _ = addPopUp("Double-click shelf edges",
                     options: EdgeDoubleClickAction.allCases,
                     titles: EdgeDoubleClickAction.allCases.map(\.title),
                     get: { Preferences.shared.edgeDoubleClickAction },
                     set: { Preferences.shared.edgeDoubleClickAction = $0 })

        addSeparator()
        addHeader("Keyboard")
        _ = addCheckbox("Shelf shortcuts active while hovering",
                        get: { Preferences.shared.hoverShortcuts },
                        set: { Preferences.shared.hoverShortcuts = $0 })
        addCaption("Requires Accessibility access so the keystroke is consumed instead of also reaching the frontmost app.")
    }
}

// MARK: - Shortcuts

final class ShortcutsPaneController: SettingsPaneController {
    override func build() {
        addCaption("Enable, disable, or assign new key combinations. Click a shortcut to record a new one.")

        addSeparator()
        addHeader("Global Shortcuts")
        for action in ShortcutAction.allCases {
            add(row(for: action))
        }

        addSeparator()
        addHeader("Shelf Shortcuts")
        addCaption("Active while the pointer is over a shelf, and whenever a shelf has keyboard focus.")
        for (title, keys) in [
            ("Quick Look", "Space"),
            ("Open selection", "↩"),
            ("Remove selection", "⌫"),
            ("Select all", "⌘A"),
            ("Copy shelf content", "⌘C"),
            ("Paste", "⌘V"),
            ("Clear shelf content", "⌘K"),
            ("Pile ↔ expanded view", "⌘E"),
            ("Show selection in new shelf", "⌘N"),
            ("Close shelf", "⌘W or ⎋"),
            ("Close all shelves", "⇧⌘W"),
        ] {
            add(staticRow(title: title, keys: keys))
        }
    }

    private func row(for action: ShortcutAction) -> NSView {
        let target = ActionTarget { control in
            guard let button = control as? NSButton else { return }
            Preferences.shared.setShortcutEnabled(button.state == .on, for: action)
            HotKeyCenter.shared.applyPreferences()
        }
        retain(target)

        let toggle = NSButton(checkboxWithTitle: action.title, target: target,
                              action: #selector(ActionTarget.fire(_:)))
        toggle.state = Preferences.shared.isShortcutEnabled(action) ? .on : .off
        track { toggle.state = Preferences.shared.isShortcutEnabled(action) ? .on : .off }

        let recorder = ShortcutRecorderView(action: action)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 120).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 22).isActive = true
        track { recorder.needsDisplay = true }

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let row = NSStackView(views: [toggle, recorder])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func staticRow(title: String, keys: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let value = NSTextField(labelWithString: keys)
        value.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        value.textColor = .secondaryLabelColor

        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        return row
    }
}

// MARK: - Ignored applications

final class IgnoredApplicationsPaneController: NSViewController,
                                               NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let removeButton = NSButton()

    private var bundleIDs: [String] = Preferences.shared.ignoredApplications

    override func loadView() {
        let container = NSView()

        let header = NSTextField(labelWithString: "Ignored applications")
        header.font = .systemFont(ofSize: 12, weight: .semibold)

        let caption = NSTextField(wrappingLabelWithString:
            "Gesture activation is suppressed while one of these apps is frontmost.")
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.title = "Application"
        column.width = 420
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let addTarget = ActionTarget { [weak self] _ in self?.addApplications() }
        let removeTarget = ActionTarget { [weak self] _ in self?.removeSelected() }
        self.actionTargets = [addTarget, removeTarget]

        let addButton = NSButton(title: "Add…", target: addTarget,
                                 action: #selector(ActionTarget.fire(_:)))
        addButton.bezelStyle = .rounded
        removeButton.title = "Remove"
        removeButton.bezelStyle = .rounded
        removeButton.target = removeTarget
        removeButton.action = #selector(ActionTarget.fire(_:))
        removeButton.isEnabled = false

        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [header, caption, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 452),
            scroll.heightAnchor.constraint(greaterThanOrEqualTo: container.heightAnchor,
                                           multiplier: 0.55),
        ])
        view = container
    }

    private var actionTargets: [ActionTarget] = []

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    private func reload() {
        bundleIDs = Preferences.shared.ignoredApplications
        tableView.reloadData()
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }

        var list = Preferences.shared.ignoredApplications
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            if !list.contains(id) { list.append(id) }
        }
        Preferences.shared.ignoredApplications = list
        reload()
    }

    private func removeSelected() {
        let doomed = tableView.selectedRowIndexes.compactMap { index -> String? in
            bundleIDs.indices.contains(index) ? bundleIDs[index] : nil
        }
        guard !doomed.isEmpty else { return }
        Preferences.shared.ignoredApplications.removeAll { doomed.contains($0) }
        reload()
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { bundleIDs.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard bundleIDs.indices.contains(row) else { return nil }
        let bundleID = bundleIDs[row]

        let imageView = NSImageView()
        let label = NSTextField(labelWithString: bundleID)
        label.font = .systemFont(ofSize: 11)

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            imageView.image = icon
            label.stringValue = FileManager.default.displayName(atPath: url.path) + "  (\(bundleID))"
        } else {
            imageView.image = NSImage(systemSymbolName: "questionmark.app",
                                      accessibilityDescription: nil)
        }

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let row = NSStackView(views: [imageView, label])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        return row
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }
}

// MARK: - About

final class AboutPaneController: SettingsPaneController {
    override func build() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill",
                             accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 38, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let name = NSTextField(labelWithString: "DropShelf")
        name.font = .systemFont(ofSize: 18, weight: .bold)
        let version = NSTextField(labelWithString: "Version \(short) (\(build))")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor

        let titles = NSStackView(views: [name, version])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        let headerRow = NSStackView(views: [icon, titles])
        headerRow.orientation = .horizontal
        headerRow.spacing = 12
        headerRow.alignment = .centerY
        add(headerRow)

        addSeparator()
        addCaption("""
            A clean-room drag-and-drop shelf for macOS. Its behaviour was \
            specified from a static analysis of a shipped shelf utility — \
            bundle metadata, Mach-O linkage, compiled Interface Builder \
            archives and localisation tables — not from its code. No \
            third-party code, artwork or resources are included; all icons are \
            SF Symbols.
            """)

        addSeparator()
        addHeader("Not implemented in this build")
        addCaption("""
            Cloud sharing (Dropover Cloud, S3, Dropbox, Google Drive, OneDrive, \
            Imgur, iCloud links) and upload history · in-app purchases · \
            widget · share extension · App Intents / Shortcuts · folder \
            monitoring · user scripts · screenshot shelf · localisation beyond \
            English.
            """)
    }
}

// MARK: - Window

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let tabController = NSTabViewController()
    private var panes: [SettingsPane: NSViewController] = [:]

    private init() {
        tabController.tabStyle = .toolbar

        let controllers: [(SettingsPane, NSViewController)] = [
            (.general, GeneralPaneController()),
            (.activation, ActivationPaneController()),
            (.shelf, ShelfPaneController()),
            (.shortcuts, ShortcutsPaneController()),
            (.applications, IgnoredApplicationsPaneController()),
            (.about, AboutPaneController()),
        ]

        for (pane, controller) in controllers {
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: SettingsWindowController.symbol(for: pane),
                                 accessibilityDescription: pane.title)
            tabController.addTabViewItem(item)
            panes[pane] = controller
        }

        let window = NSWindow(contentViewController: tabController)
        window.title = "DropShelf Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 460))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func symbol(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return "gearshape"
        case .activation: return "hand.draw"
        case .shelf: return "rectangle.stack"
        case .shortcuts: return "keyboard"
        case .applications: return "app.badge"
        case .about: return "info.circle"
        }
    }

    func show(pane: SettingsPane = .general) {
        if let index = SettingsPane.allCases.firstIndex(of: pane) {
            tabController.selectedTabViewItemIndex = index
        }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        (panes[pane] as? SettingsPaneController)?.refresh()
    }
}
