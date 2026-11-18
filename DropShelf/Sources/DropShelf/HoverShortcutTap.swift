import AppKit

/// Delivers shelf shortcuts while the pointer merely *hovers* a shelf, which
/// is what `keyboard-action-settings.section.shelf.description` describes.
///
/// A global `NSEvent` monitor cannot swallow the keystroke, so the key would
/// also reach whatever app is frontmost. A session event tap can return `nil`
/// to consume it, so that is what this uses. Requires Accessibility trust;
/// without it `tapCreate` returns `nil` and hover shortcuts simply stay off.
final class HoverShortcutTap {
    static let shared = HoverShortcutTap()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        guard AccessibilityGate.isTrusted else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: hoverTapCallback,
                                           userInfo: nil) else {
            NSLog("DropShelf: could not create key event tap; hover shortcuts disabled")
            return
        }

        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func reenable() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

private func hoverTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        HoverShortcutTap.shared.reenable()
        return Unmanaged.passUnretained(event)
    }

    guard Preferences.shared.hoverShortcuts,
          let shelf = ShelfStore.shared.hoveredShelf,
          let nsEvent = NSEvent(cgEvent: event) else {
        return Unmanaged.passUnretained(event)
    }

    // Our own windows handle their keys through the normal responder chain.
    if NSApp.isActive, shelf.window?.isKeyWindow == true {
        return Unmanaged.passUnretained(event)
    }

    return shelf.handleShelfKey(nsEvent) ? nil : Unmanaged.passUnretained(event)
}
