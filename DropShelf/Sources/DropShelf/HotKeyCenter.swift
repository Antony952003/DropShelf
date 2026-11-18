import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcuts via Carbon's `RegisterEventHotKey`.
///
/// Dropover links `Carbon` (ANALYSIS.md §2) for the same reason: Carbon hot
/// keys are the only system-wide shortcut API that does not require
/// Accessibility trust.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: Installation

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyEventHandler,
                            1,
                            &spec,
                            nil,
                            &eventHandler)
    }

    /// Registers `shortcut` and returns a token, or `nil` if the system
    /// refused it (usually because another app owns the combination).
    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x44_53_48_4B), id: id) // 'DSHK'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         HotKeyCenter.carbonModifiers(from: shortcut.modifierFlags),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return nil }

        refs[id] = hotKeyRef
        handlers[id] = handler
        return id
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    // MARK: Modifier translation

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    // MARK: Applying preferences

    /// Re-registers every enabled action from `Preferences`.
    func applyPreferences() {
        unregisterAll()
        for action in ShortcutAction.allCases {
            guard Preferences.shared.isShortcutEnabled(action) else { continue }
            let shortcut = Preferences.shared.shortcut(for: action)
            let registered = register(shortcut) {
                HotKeyCenter.perform(action)
            }
            if registered == nil {
                NSLog("DropShelf: system refused shortcut \(shortcut.displayString) for \(action.rawValue)")
            }
        }
    }

    static func perform(_ action: ShortcutAction) {
        let store = ShelfStore.shared
        switch action {
        case .newShelf:
            store.createShelf(at: NSEvent.mouseLocation)
        case .newClipboardShelf:
            let items = ShelfItem.items(from: NSPasteboard.general)
            store.createShelf(at: NSEvent.mouseLocation, items: items)
        case .reopenLastClosedShelf:
            store.reopenLastClosed()
        case .closeAllShelves:
            store.closeAll()
        case .toggleDockingForAllShelves:
            store.toggleDockingForAllShelves()
        }
    }
}

/// Carbon requires a bare C function pointer.
private func hotKeyEventHandler(_ callRef: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    DispatchQueue.main.async {
        HotKeyCenter.shared.fire(id: hotKeyID.id)
    }
    return noErr
}
