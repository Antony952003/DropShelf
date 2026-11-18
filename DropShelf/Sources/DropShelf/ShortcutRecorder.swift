import AppKit

/// Click-to-record shortcut field.
///
/// Enforces the same three rules Dropover's `keyboard-action-validator`
/// reports: a combination must carry a modifier, must not duplicate another
/// DropShelf action, and must not be one the system already owns (detected by
/// `RegisterEventHotKey` refusing it).
final class ShortcutRecorderView: NSView {

    var action: ShortcutAction
    var onChange: (() -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    init(action: ShortcutAction) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // escape cancels
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])

        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
            report("The recorded shortcut is invalid. Shortcuts must include ⌘ Command, ⌃ Control, or ⌥ Option.")
            return
        }

        let candidate = Shortcut(keyCode: event.keyCode, modifiers: flags.rawValue)

        if let conflict = Preferences.shared.conflictingAction(for: candidate, excluding: action) {
            report("This combination is already in use by “\(conflict.title)”. Try a different one.")
            return
        }

        // Probe the system: if Carbon refuses the combination, something else
        // owns it globally.
        HotKeyCenter.shared.unregisterAll()
        let probe = HotKeyCenter.shared.register(candidate) {}
        HotKeyCenter.shared.unregisterAll()
        guard probe != nil else {
            HotKeyCenter.shared.applyPreferences()
            report("The recorded shortcut is already in use by the system. Try a different combination.")
            return
        }

        Preferences.shared.setShortcut(candidate, for: action)
        Preferences.shared.setShortcutEnabled(true, for: action)
        HotKeyCenter.shared.applyPreferences()
        isRecording = false
        window?.makeFirstResponder(nil)
        onChange?()
        needsDisplay = true
    }

    private func report(_ message: String) {
        isRecording = false
        needsDisplay = true
        let alert = NSAlert()
        alert.messageText = "Cannot Assign Shortcut"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                     : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording
            ? "Type shortcut…"
            : Preferences.shared.shortcut(for: action).displayString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: isRecording ? .regular : .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        let size = attributed.size()
        attributed.draw(in: NSRect(x: rect.minX,
                                   y: rect.midY - size.height / 2,
                                   width: rect.width,
                                   height: size.height))
    }
}
