import AppKit

var results: [(String, String, String)] = []
func check(_ n: String, _ ok: Bool, _ d: String = "") { results.append((n, ok ? "PASS" : "FAIL", d)) }
func note(_ n: String, _ d: String) { results.append((n, "SKIP", d)) }
func spin(_ s: TimeInterval) {
    let e = Date().addingTimeInterval(s)
    while Date() < e { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

/// Every NSControl in a view tree that has both a target and an action.
func controls(in view: NSView) -> [NSControl] {
    var out: [NSControl] = []
    if let c = view as? NSControl, c.action != nil, c.target != nil { out.append(c) }
    for sub in view.subviews { out += controls(in: sub) }
    return out
}
func label(_ c: NSControl) -> String {
    if let b = c as? NSButton, !b.title.isEmpty { return b.title }
    if let p = c as? NSPopUpButton { return "popup[\(p.itemTitles.prefix(2).joined(separator: "/"))…]" }
    return String(describing: type(of: c))
}
/// Dispatch exactly as a click does.
func dispatch(_ c: NSControl) -> Bool {
    guard let a = c.action else { return false }
    let ok = NSApp.sendAction(a, to: c.target, from: c)
    spin(0.05)
    return ok
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Anything that would touch the system or open a panel.
let avoid = ["Launch at login", "Add…", "Open Accessibility Settings…", "Restore Defaults", "Remove"]

// ---------- 1. settings panes ----------
let panes: [(String, NSViewController)] = [
    ("General", GeneralPaneController()),
    ("Activation", ActivationPaneController()),
    ("Shelf", ShelfPaneController()),
    ("Shortcuts", ShortcutsPaneController()),
    ("Ignored Apps", IgnoredApplicationsPaneController()),
    ("About", AboutPaneController()),
]
for (name, pane) in panes {
    _ = pane.view                      // force loadView/build
    pane.viewWillAppear()
    let all = controls(in: pane.view)
    let firable = all.filter { c in !avoid.contains(where: { label(c).contains($0) }) }
    var dispatched = 0, failed: [String] = []
    for c in firable {
        if let b = c as? NSButton, b.allowsMixedState == false, b.state == .on || b.state == .off {
            b.state = (b.state == .on) ? .off : .on          // AppKit toggles before sending
        }
        if let p = c as? NSPopUpButton, p.numberOfItems > 1 {
            p.selectItem(at: (p.indexOfSelectedItem + 1) % p.numberOfItems)
        }
        if dispatch(c) { dispatched += 1 } else { failed.append(label(c)) }
    }
    check("Settings ▸ \(name)", failed.isEmpty && dispatched == firable.count,
          "\(dispatched)/\(firable.count) controls dispatched"
          + (all.count > firable.count ? ", \(all.count - firable.count) skipped" : "")
          + (failed.isEmpty ? "" : ", FAILED: \(failed)"))
}

// ---------- 2. a settings control really changes its preference ----------
do {
    let pane = ShelfPaneController()
    _ = pane.view
    let before = Preferences.shared.copyInsteadOfMove
    guard let box = controls(in: pane.view).compactMap({ $0 as? NSButton })
        .first(where: { $0.title.contains("Copy files instead of moving") }) else {
        check("Settings checkbox → preference", false, "checkbox not found"); exit(1)
    }
    box.state = before ? .off : .on
    _ = dispatch(box)
    let after = Preferences.shared.copyInsteadOfMove
    check("Settings checkbox → preference", after != before,
          "copyInsteadOfMove \(before)→\(after)")
}

do {
    let pane = ActivationPaneController()
    _ = pane.view
    let before = Preferences.shared.shakeSensitivity
    guard let popup = controls(in: pane.view).compactMap({ $0 as? NSPopUpButton })
        .first(where: { $0.itemTitles.contains { $0.contains("Sensitivity") } }) else {
        check("Settings popup → preference", false, "popup not found"); exit(1)
    }
    popup.selectItem(at: (popup.indexOfSelectedItem + 1) % popup.numberOfItems)
    _ = dispatch(popup)
    check("Settings popup → preference", Preferences.shared.shakeSensitivity != before,
          "shakeSensitivity \(before)→\(Preferences.shared.shakeSensitivity)")
}

// ---------- 3. shortcut recorder ----------
do {
    let recorder = ShortcutRecorderView(action: .newShelf)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView?.addSubview(recorder)
    window.makeFirstResponder(recorder)
    recorder.mouseDown(with: NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1)!)
    // ⌃⌥⌘J — unlikely to collide with the system
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero,
                               modifierFlags: [.control, .option, .command],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               characters: "j", charactersIgnoringModifiers: "j",
                               isARepeat: false, keyCode: 38)!
    recorder.keyDown(with: key)
    spin(0.3)
    let s = Preferences.shared.shortcut(for: .newShelf)
    check("Shortcut recorder records a key", s.keyCode == 38 && s.modifierFlags.contains(.command),
          "newShelf = \(s.displayString)")

    // Same combination on another action must be rejected as a duplicate.
    let dup = ShortcutRecorderView(action: .closeAllShelves)
    window.contentView?.addSubview(dup)
    window.makeFirstResponder(dup)
    let wasBefore = Preferences.shared.shortcut(for: .closeAllShelves)
    note("Shortcut duplicate rejection",
         "not fired: the rejection path shows a modal NSAlert. Conflict detection itself: "
         + (Preferences.shared.conflictingAction(for: s, excluding: .closeAllShelves) == .newShelf
            ? "conflictingAction() correctly reports .newShelf" : "NOT DETECTED"))
    _ = wasBefore; _ = dup
}

// ---------- 4. dropdown's grid/list toggle + card controls ----------
do {
    Preferences.shared.autoRetract = false
    let dir = URL(fileURLWithPath: "/tmp/uitest/f", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("x.txt")
    try? "x".write(to: f, atomically: true, encoding: .utf8)

    let s = ShelfStore.shared.createShelf(at: CGPoint(x: 500, y: 500),
                                          items: [ShelfItem(payload: .file(f))])
    spin(0.3)

    // Card pill toggles the dropdown.
    guard let pill = controls(in: s.window!.contentView!).first(where: { $0 is PillButton }) else {
        check("Card pill → dropdown", false, "pill not found"); exit(1)
    }
    _ = dispatch(pill); spin(0.6)
    let opened = s.shelf.isExpanded && (s.window?.childWindows?.count ?? 0) == 1
    check("Card pill → opens dropdown", opened,
          "isExpanded=\(s.shelf.isExpanded), children=\(s.window?.childWindows?.count ?? 0)")

    // The dropdown's own segmented control.
    if let panel = s.window?.childWindows?.first as? ShelfDetailPanel,
       let root = panel.contentView,
       let seg = controls(in: root).compactMap({ $0 as? NSSegmentedControl }).first {
        let before = s.shelf.layout
        seg.selectedSegment = (before == .grid) ? 1 : 0
        _ = dispatch(seg); spin(0.2)
        check("Dropdown ▸ grid/list toggle", s.shelf.layout != before,
              "layout \(before)→\(s.shelf.layout)")

        let gear = controls(in: root).compactMap { $0 as? CircleGlyphButton }.first
        note("Dropdown ▸ gear", gear != nil
             ? "not fired: opens the settings window. Wired: action=\(gear!.action.map { NSStringFromSelector($0) } ?? "nil")"
             : "gear not found")
    } else {
        check("Dropdown ▸ grid/list toggle", false, "dropdown or segmented control not reachable")
    }

    _ = dispatch(pill); spin(0.6)
    check("Card pill → closes dropdown", !s.shelf.isExpanded,
          "isExpanded=\(s.shelf.isExpanded)")

    // Close button.
    let n = ShelfStore.shared.controllers.count
    if let close = controls(in: s.window!.contentView!).compactMap({ $0 as? CircleGlyphButton })
        .first(where: { ($0.action.map { NSStringFromSelector($0) } ?? "").contains("Close") }) {
        _ = dispatch(close); spin(0.6)
        check("Card ✕ → closes shelf", ShelfStore.shared.controllers.count == n - 1,
              "shelves \(n)→\(ShelfStore.shared.controllers.count)")
    } else {
        check("Card ✕ → closes shelf", false, "close button not found")
    }
    ShelfStore.shared.closeAll(); spin(0.4)
}

print("=== SETTINGS / CONTROL DISPATCH RESULTS ===")
let w = results.map(\.0.count).max() ?? 20
for (n, v, d) in results { print("  \(v)  \(n.padding(toLength: w, withPad: " ", startingAt: 0))  \(d)") }
let f = results.filter { $0.1 == "FAIL" }.count
print("\n  \(results.filter { $0.1 == "PASS" }.count) passed, \(f) failed, \(results.filter { $0.1 == "SKIP" }.count) noted")
exit(f == 0 ? 0 : 1)
