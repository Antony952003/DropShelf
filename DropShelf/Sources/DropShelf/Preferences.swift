import AppKit
import Combine
import ServiceManagement

// MARK: - Option types
//
// Each enum below mirrors a choice observed in Dropover's Localizable.strings
// (see ANALYSIS.md §4). The *behaviour* is reimplemented; none of the original
// code or strings are reused.

enum ActivationModifier: String, CaseIterable, Codable {
    case off, command, control, shift

    var title: String {
        switch self {
        case .off: return "Off"
        case .command: return "Using ⌘ Command key"
        case .control: return "Using ⌃ Control key"
        case .shift: return "Using ⇧ Shift key"
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .off: return nil
        case .command: return .command
        case .control: return .control
        case .shift: return .shift
        }
    }
}

enum ShakeSensitivity: String, CaseIterable, Codable {
    case normal, high, highest

    var title: String {
        switch self {
        case .normal: return "Default Sensitivity"
        case .high: return "High Sensitivity"
        case .highest: return "Highest Sensitivity"
        }
    }

    /// Number of horizontal direction reversals required to fire.
    var reversalsRequired: Int {
        switch self {
        case .normal: return 4
        case .high: return 3
        case .highest: return 2
        }
    }

    /// Minimum travel (points) a leg must cover to count as a reversal.
    var minimumLeg: CGFloat {
        switch self {
        case .normal: return 42
        case .high: return 28
        case .highest: return 18
        }
    }

    /// Reversals must all happen inside this window.
    var window: TimeInterval { 0.9 }
}

enum NotchHighlightMode: String, CaseIterable, Codable {
    case always, hover, never

    var title: String {
        switch self {
        case .always: return "Always Highlight While Dragging"
        case .hover: return "Highlight When Hovering Over Notch"
        case .never: return "No Highlighting"
        }
    }
}

enum EdgeDoubleClickAction: String, CaseIterable, Codable {
    case dock, retract, none

    var title: String {
        switch self {
        case .dock: return "Dock Shelf"
        case .retract: return "Retract Shelf"
        case .none: return "Does Nothing"
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Codable {
    case traditional, document, documentTilted

    var title: String {
        switch self {
        case .traditional: return "Traditional"
        case .document: return "Document"
        case .documentTilted: return "Document 2"
        }
    }

    var symbolName: String {
        switch self {
        case .traditional: return "tray.and.arrow.down"
        case .document: return "doc.on.doc"
        case .documentTilted: return "doc.text.below.ecg"
        }
    }
}

enum ShelfLayout: String, Codable {
    case grid, list
}

// MARK: - Shortcut value

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags.rawValue, device-independent only

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        var s = ""
        let f = modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

/// Identifiers for every globally-registrable action.
enum ShortcutAction: String, CaseIterable, Codable {
    case newShelf
    case newClipboardShelf
    case reopenLastClosedShelf
    case closeAllShelves
    case toggleDockingForAllShelves

    var title: String {
        switch self {
        case .newShelf: return "New Shelf"
        case .newClipboardShelf: return "New Clipboard Shelf"
        case .reopenLastClosedShelf: return "Reopen Last Closed Shelf"
        case .closeAllShelves: return "Close All Shelves"
        case .toggleDockingForAllShelves: return "Toggle Docking for All Shelves"
        }
    }

    var defaultShortcut: Shortcut {
        let cmdCtrlOpt = NSEvent.ModifierFlags([.command, .control, .option]).rawValue
        switch self {
        case .newShelf: return Shortcut(keyCode: 45, modifiers: cmdCtrlOpt)             // N
        case .newClipboardShelf: return Shortcut(keyCode: 9, modifiers: cmdCtrlOpt)     // V
        case .reopenLastClosedShelf: return Shortcut(keyCode: 17, modifiers: cmdCtrlOpt) // T
        case .closeAllShelves: return Shortcut(keyCode: 13, modifiers: cmdCtrlOpt)      // W
        case .toggleDockingForAllShelves: return Shortcut(keyCode: 2, modifiers: cmdCtrlOpt) // D
        }
    }
}

// MARK: - Preferences store

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let shakeEnabled = "activation.shake.enabled"
        static let shakeSensitivity = "activation.shake.sensitivity"
        static let modifier = "activation.modifier"
        static let notchEnabled = "activation.notch.enabled"
        static let notchHighlight = "activation.notch.highlight"
        static let copyInsteadOfMove = "shelf.copyInsteadOfMove"
        static let forcePlainText = "shelf.forcePlainText"
        static let snapWindows = "shelf.snap"
        static let autoRetract = "shelf.autoRetract"
        static let closeAfterDrag = "shelf.closeAfterDrag"
        static let restrictToSpace = "shelf.restrictToSpace"
        static let colorLabels = "shelf.colorLabels"
        static let edgeDoubleClick = "shelf.edgeDoubleClick"
        static let defaultLayout = "shelf.defaultLayout"
        static let hoverShortcuts = "shelf.hoverShortcuts"
        static let screenshotShelf = "shelf.screenshotShelf"
        static let showInMenuBar = "app.showInMenuBar"
        static let showInDock = "app.showInDock"
        static let menuBarIcon = "app.menuBarIcon"
        static let launchAtLogin = "app.launchAtLogin"
        static let ignoredApplications = "app.ignoredApplications"
        static let shortcuts = "app.shortcuts"
        static let shortcutsEnabled = "app.shortcutsEnabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.shakeEnabled: true,
            Key.shakeSensitivity: ShakeSensitivity.normal.rawValue,
            Key.modifier: ActivationModifier.off.rawValue,
            Key.notchEnabled: true,
            Key.notchHighlight: NotchHighlightMode.hover.rawValue,
            Key.copyInsteadOfMove: false,
            Key.forcePlainText: false,
            Key.snapWindows: true,
            Key.autoRetract: true,
            Key.closeAfterDrag: false,
            Key.restrictToSpace: false,
            Key.colorLabels: true,
            Key.edgeDoubleClick: EdgeDoubleClickAction.dock.rawValue,
            Key.defaultLayout: ShelfLayout.grid.rawValue,
            Key.hoverShortcuts: true,
            Key.screenshotShelf: true,
            Key.showInMenuBar: true,
            Key.showInDock: false,
            Key.menuBarIcon: MenuBarIconStyle.traditional.rawValue,
            Key.launchAtLogin: false,
            Key.ignoredApplications: [String](),
        ])
    }

    // Generic accessors ----------------------------------------------------

    private func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }

    private func setBool(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
        objectWillChange.send()
        NotificationCenter.default.post(name: Preferences.didChange, object: key)
    }

    private func enumValue<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let v = T(rawValue: raw) else { return fallback }
        return v
    }

    private func setEnum<T: RawRepresentable>(_ value: T, _ key: String) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
        objectWillChange.send()
        NotificationCenter.default.post(name: Preferences.didChange, object: key)
    }

    static let didChange = Notification.Name("DropShelf.preferencesDidChange")

    // MARK: Activation

    var shakeEnabled: Bool {
        get { bool(Key.shakeEnabled) }
        set { setBool(newValue, Key.shakeEnabled) }
    }

    var shakeSensitivity: ShakeSensitivity {
        get { enumValue(Key.shakeSensitivity, .normal) }
        set { setEnum(newValue, Key.shakeSensitivity) }
    }

    var activationModifier: ActivationModifier {
        get { enumValue(Key.modifier, .off) }
        set { setEnum(newValue, Key.modifier) }
    }

    var notchEnabled: Bool {
        get { bool(Key.notchEnabled) }
        set { setBool(newValue, Key.notchEnabled) }
    }

    var notchHighlight: NotchHighlightMode {
        get { enumValue(Key.notchHighlight, .hover) }
        set { setEnum(newValue, Key.notchHighlight) }
    }

    // MARK: Shelf interaction

    var copyInsteadOfMove: Bool {
        get { bool(Key.copyInsteadOfMove) }
        set { setBool(newValue, Key.copyInsteadOfMove) }
    }

    var forcePlainText: Bool {
        get { bool(Key.forcePlainText) }
        set { setBool(newValue, Key.forcePlainText) }
    }

    var snapWindows: Bool {
        get { bool(Key.snapWindows) }
        set { setBool(newValue, Key.snapWindows) }
    }

    var autoRetract: Bool {
        get { bool(Key.autoRetract) }
        set { setBool(newValue, Key.autoRetract) }
    }

    var closeAfterDrag: Bool {
        get { bool(Key.closeAfterDrag) }
        set { setBool(newValue, Key.closeAfterDrag) }
    }

    var restrictToCurrentSpace: Bool {
        get { bool(Key.restrictToSpace) }
        set { setBool(newValue, Key.restrictToSpace) }
    }

    var useColorLabels: Bool {
        get { bool(Key.colorLabels) }
        set { setBool(newValue, Key.colorLabels) }
    }

    var edgeDoubleClickAction: EdgeDoubleClickAction {
        get { enumValue(Key.edgeDoubleClick, .dock) }
        set { setEnum(newValue, Key.edgeDoubleClick) }
    }

    var defaultLayout: ShelfLayout {
        get { enumValue(Key.defaultLayout, .grid) }
        set { setEnum(newValue, Key.defaultLayout) }
    }

    var hoverShortcuts: Bool {
        get { bool(Key.hoverShortcuts) }
        set { setBool(newValue, Key.hoverShortcuts) }
    }

    /// `preferences.screenshots.title` — new screenshots land on a shelf.
    var screenshotShelf: Bool {
        get { bool(Key.screenshotShelf) }
        set { setBool(newValue, Key.screenshotShelf) }
    }

    // MARK: App presence

    var showInMenuBar: Bool {
        get { bool(Key.showInMenuBar) }
        set { setBool(newValue, Key.showInMenuBar) }
    }

    var showInDock: Bool {
        get { bool(Key.showInDock) }
        set { setBool(newValue, Key.showInDock) }
    }

    var menuBarIcon: MenuBarIconStyle {
        get { enumValue(Key.menuBarIcon, .traditional) }
        set { setEnum(newValue, Key.menuBarIcon) }
    }

    var ignoredApplications: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApplications) ?? [] }
        set {
            defaults.set(newValue, forKey: Key.ignoredApplications)
            objectWillChange.send()
        }
    }

    /// `SMAppService` is the source of truth; the stored flag is only a cache
    /// so the UI can render before the service is queried.
    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return bool(Key.launchAtLogin)
        }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            objectWillChange.send()
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("DropShelf: login item change failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Shortcuts

    func shortcut(for action: ShortcutAction) -> Shortcut {
        guard
            let map = defaults.dictionary(forKey: Key.shortcuts) as? [String: [String: NSNumber]],
            let entry = map[action.rawValue],
            let code = entry["keyCode"]?.uint16Value,
            let mods = entry["modifiers"]?.uintValue
        else { return action.defaultShortcut }
        return Shortcut(keyCode: code, modifiers: mods)
    }

    func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        var map = (defaults.dictionary(forKey: Key.shortcuts) as? [String: [String: NSNumber]]) ?? [:]
        map[action.rawValue] = ["keyCode": NSNumber(value: shortcut.keyCode),
                                "modifiers": NSNumber(value: shortcut.modifiers)]
        defaults.set(map, forKey: Key.shortcuts)
        objectWillChange.send()
        NotificationCenter.default.post(name: Preferences.didChange, object: Key.shortcuts)
    }

    func isShortcutEnabled(_ action: ShortcutAction) -> Bool {
        guard let map = defaults.dictionary(forKey: Key.shortcutsEnabled) as? [String: Bool],
              let v = map[action.rawValue] else { return true }
        return v
    }

    func setShortcutEnabled(_ enabled: Bool, for action: ShortcutAction) {
        var map = (defaults.dictionary(forKey: Key.shortcutsEnabled) as? [String: Bool]) ?? [:]
        map[action.rawValue] = enabled
        defaults.set(map, forKey: Key.shortcutsEnabled)
        objectWillChange.send()
        NotificationCenter.default.post(name: Preferences.didChange, object: Key.shortcutsEnabled)
    }

    /// Returns the action already using `shortcut`, if any — used to reject
    /// duplicates the way Dropover's keyboard pane does.
    func conflictingAction(for shortcut: Shortcut, excluding action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { other in
            other != action && self.shortcut(for: other) == shortcut && isShortcutEnabled(other)
        }
    }

    func restoreDefaults() {
        for key in [Key.shakeEnabled, Key.shakeSensitivity, Key.modifier, Key.notchEnabled,
                    Key.notchHighlight, Key.copyInsteadOfMove, Key.forcePlainText,
                    Key.snapWindows, Key.autoRetract, Key.closeAfterDrag, Key.restrictToSpace,
                    Key.colorLabels, Key.edgeDoubleClick, Key.defaultLayout, Key.hoverShortcuts,
                    Key.screenshotShelf,
                    Key.menuBarIcon, Key.shortcuts, Key.shortcutsEnabled] {
            defaults.removeObject(forKey: key)
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
    }
}

// MARK: - Key code names

enum KeyCodeNames {
    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        109: "F10", 111: "F12", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func name(for keyCode: UInt16) -> String {
        table[keyCode] ?? "Key \(keyCode)"
    }
}
