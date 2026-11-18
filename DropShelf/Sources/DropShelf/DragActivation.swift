import AppKit
import ApplicationServices

/// Watches system-wide mouse activity for the two gesture activations Dropover
/// exposes: shake-while-dragging and hold-a-modifier-while-dragging
/// (`preferences.shelf.shake-gesture`, `preferences.shelf.modifier-key`).
///
/// Mouse monitoring needs Accessibility trust; without it the monitors install
/// but never fire, which is why `AccessibilityGate` exists.
final class DragActivationMonitor {
    static let shared = DragActivationMonitor()

    /// Called with the current mouse location when a gesture fires.
    var onActivate: ((CGPoint) -> Void)?
    /// Called when a left-button drag starts / ends, so the notch target can
    /// show and hide itself.
    var onDragStateChange: ((Bool) -> Void)?

    private var monitors: [Any] = []
    private var isDragging = false
    private var hasFiredThisDrag = false
    /// Dragging a shelf around must not look like a shake gesture.
    private var startedOnOwnWindow = false

    // Shake state
    private var legStartX: CGFloat = 0
    private var direction: CGFloat = 0
    private var reversals = 0
    private var windowStart: TimeInterval = 0

    private init() {}

    // MARK: Lifecycle

    func start() {
        stop()
        add(.leftMouseDown) { [weak self] event in self?.handleMouseDown(event) }
        add(.leftMouseUp) { [weak self] event in self?.handleMouseUp(event) }
        add(.leftMouseDragged) { [weak self] event in self?.handleMouseDragged(event) }
        add(.flagsChanged) { [weak self] event in self?.handleFlagsChanged(event) }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        resetDrag()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        // Local monitor so gestures also work over our own windows.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    // MARK: Event handling

    private func handleMouseDown(_ event: NSEvent) {
        isDragging = false
        hasFiredThisDrag = false
        let location = NSEvent.mouseLocation
        startedOnOwnWindow = ShelfStore.shared.controllers.contains { controller in
            controller.window?.frame.contains(location) == true
        }
        resetShake(at: location.x)
    }

    private func handleMouseUp(_ event: NSEvent) {
        if isDragging { onDragStateChange?(false) }
        resetDrag()
    }

    private func handleMouseDragged(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        if !isDragging {
            isDragging = true
            resetShake(at: location.x)
            if !startedOnOwnWindow { onDragStateChange?(true) }
        }

        guard Preferences.shared.shakeEnabled, !hasFiredThisDrag, !startedOnOwnWindow else { return }
        guard !isFrontmostApplicationIgnored() else { return }

        let sensitivity = Preferences.shared.shakeSensitivity
        let now = ProcessInfo.processInfo.systemUptime
        let dx = location.x - legStartX

        if abs(dx) < sensitivity.minimumLeg { return }

        let newDirection: CGFloat = dx > 0 ? 1 : -1
        if direction == 0 {
            direction = newDirection
            legStartX = location.x
            windowStart = now
            reversals = 0
            return
        }

        if newDirection != direction {
            if now - windowStart > sensitivity.window {
                // Too slow to count as one gesture — start a fresh window.
                reversals = 1
                windowStart = now
            } else {
                reversals += 1
            }
            direction = newDirection
            legStartX = location.x

            if reversals >= sensitivity.reversalsRequired {
                fire(at: location)
            }
        } else {
            legStartX = location.x
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let required = Preferences.shared.activationModifier.flag else { return }
        guard isDragging, !hasFiredThisDrag, !startedOnOwnWindow else { return }
        guard !isFrontmostApplicationIgnored() else { return }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(required) else {
            return
        }
        fire(at: NSEvent.mouseLocation)
    }

    private func fire(at point: CGPoint) {
        hasFiredThisDrag = true
        resetShake(at: point.x)
        onActivate?(point)
    }

    private func resetDrag() {
        isDragging = false
        hasFiredThisDrag = false
        direction = 0
        reversals = 0
    }

    private func resetShake(at x: CGFloat) {
        legStartX = x
        direction = 0
        reversals = 0
        windowStart = ProcessInfo.processInfo.systemUptime
    }

    /// `preferences.ignored-applications` — never activate while one of these
    /// apps is frontmost.
    private func isFrontmostApplicationIgnored() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Preferences.shared.ignoredApplications.contains(bundleID)
    }
}

// MARK: - Accessibility permission

enum AccessibilityGate {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Returns the trust state *before* the prompt.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    private static let warnedKey = "app.hasWarnedAboutAccessibility"

    /// One-time nudge when gesture activation is on but trust is missing.
    static func warnIfNeeded() {
        guard !isTrusted else { return }
        guard !UserDefaults.standard.bool(forKey: warnedKey) else { return }
        let preferences = Preferences.shared
        guard preferences.shakeEnabled || preferences.activationModifier != .off else { return }
        UserDefaults.standard.set(true, forKey: warnedKey)

        let alert = NSAlert()
        alert.messageText = "DropShelf needs Accessibility access"
        alert.informativeText = """
            Shake and modifier-key activation read mouse events system-wide, \
            which macOS gates behind Privacy & Security ▸ Accessibility.

            Keyboard shortcuts, the notch drop target, and the menu bar work \
            without it.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            requestTrust()
            openSystemSettings()
        }
    }
}
