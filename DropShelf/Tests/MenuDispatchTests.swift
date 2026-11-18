// Exercises the ⋯ action menu and the menu-bar menu through NSApp.sendAction,
// the dispatch path a real click uses. See Tests/README.md for why that matters.
import AppKit

var results: [(String, String, String)] = []
func check(_ n: String, _ ok: Bool, _ d: String = "") { results.append((n, ok ? "PASS" : "FAIL", d)) }
func note(_ n: String, _ d: String) { results.append((n, "SKIP", d)) }
func spin(_ s: TimeInterval) {
    let e = Date().addingTimeInterval(s)
    while Date() < e { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}
func waitUntil(_ t: TimeInterval, _ c: () -> Bool) -> Bool {
    let e = Date().addingTimeInterval(t)
    while Date() < e { if c() { return true }; RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    return c()
}
func flatten(_ m: NSMenu, _ p: String = "") -> [(String, NSMenuItem)] {
    var o: [(String, NSMenuItem)] = []
    for i in m.items where !i.isSeparatorItem {
        let l = p.isEmpty ? i.title : "\(p) ▸ \(i.title)"
        o.append((l, i)); if let s = i.submenu { o += flatten(s, l) }
    }
    return o
}
@discardableResult
func click(_ m: NSMenu, _ needle: String) -> Bool {
    guard let item = flatten(m).first(where: { $0.0.contains(needle) })?.1,
          let action = item.action else { return false }
    let ok = NSApp.sendAction(action, to: item.target, from: item)
    spin(0.3)
    return ok
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Preferences.shared.autoRetract = false

let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "dropshelf-menutests", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
try? "a".write(to: a, atomically: true, encoding: .utf8)
try? "b".write(to: b, atomically: true, encoding: .utf8)
func shelf(_ u: [URL]) -> ShelfWindowController {
    ShelfStore.shared.createShelf(at: CGPoint(x: 500, y: 500), items: u.map { ShelfItem(payload: .file($0)) })
}

do { let s = shelf([a, b]); spin(0.3)
     let n = ShelfStore.shared.controllers.count
     check("⋯ Move to New Shelf", click(s.actionMenu(for: []), "Move to New Shelf")
           && ShelfStore.shared.controllers.count == n + 1 && s.shelf.items.isEmpty,
           "shelves \(n)→\(ShelfStore.shared.controllers.count), source \(s.shelf.items.count) items")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a, b]); spin(0.3)
     let n = ShelfStore.shared.controllers.count
     check("⋯ Show in New Shelf", click(s.actionMenu(for: []), "Show in New Shelf")
           && ShelfStore.shared.controllers.count == n + 1 && s.shelf.items.count == 2)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3); NSPasteboard.general.clearContents()
     click(s.actionMenu(for: []), "Copy ")
     let u = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
     check("⋯ Copy", u.contains { $0.lastPathComponent == "a.txt" }, "pasteboard \(u.map(\.lastPathComponent))")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([b as NSURL])
     click(s.actionMenu(for: []), "Add From Clipboard")
     check("⋯ Add From Clipboard", s.shelf.items.count == 2, "\(s.shelf.items.count) items")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a, b]); spin(0.3)
     click(s.actionMenu(for: []), "Compress")
     check("⋯ Compress", waitUntil(20) { s.shelf.items.contains { $0.displayName.hasSuffix(".zip") } })
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a, b]); spin(0.3)
     click(s.actionMenu(for: [s.shelf.items[0]]), "Remove From Shelf")
     check("⋯ Remove From Shelf", s.shelf.items.count == 1, "\(s.shelf.items.count) left")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a, b]); spin(0.3)
     click(s.actionMenu(for: []), "Clear Shelf")
     check("⋯ Clear Shelf", s.shelf.items.isEmpty)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a, b]); spin(0.3)
     click(s.actionMenu(for: []), "Show Files"); spin(0.5)
     let ok1 = s.shelf.isExpanded && (s.window?.childWindows?.count ?? 0) == 1
     click(s.actionMenu(for: []), "Hide Files"); spin(0.6)
     check("⋯ Show / Hide Files", ok1 && !s.shelf.isExpanded)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     click(s.actionMenu(for: []), "Dock to Left Edge"); spin(0.6)
     let ok1 = s.shelf.dockedEdge == .left
     click(s.actionMenu(for: []), "Undock"); spin(0.6)
     check("⋯ Dock / Undock", ok1 && s.shelf.dockedEdge == nil)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     click(s.actionMenu(for: []), "Move Aside"); spin(0.9)
     let ok1 = s.shelf.isParked
     click(s.actionMenu(for: []), "Bring Back"); spin(0.9)
     check("⋯ Move Aside / Bring Back", ok1 && !s.shelf.isParked)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     click(s.actionMenu(for: []), "View As ▸ List")
     let ok1 = s.shelf.layout == .list
     click(s.actionMenu(for: []), "View As ▸ Icons")
     check("⋯ View As", ok1 && s.shelf.layout == .grid)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     click(s.actionMenu(for: []), "Pin Shelf")
     let ok1 = s.shelf.pinned
     click(s.actionMenu(for: []), "Unpin Shelf")
     check("⋯ Pin / Unpin", ok1 && !s.shelf.pinned)
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     let n = ShelfStore.shared.controllers.count
     click(s.actionMenu(for: []), "Close")
     check("⋯ Close", waitUntil(3) { !ShelfStore.shared.controllers.contains { $0 === s } },
           "shelves \(n)→\(ShelfStore.shared.controllers.count)")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     let e = flatten(s.actionMenu(for: [])).first { $0.0.hasPrefix("Open With ▸") }
     check("⋯ Open With entries dispatchable", e?.1.action != nil && e?.1.target != nil,
           "action=\(e?.1.action.map { NSStringFromSelector($0) } ?? "nil")")
     let names = flatten(s.actionMenu(for: [])).filter { $0.0.hasPrefix("Open With ▸") }.map(\.0)
     check("⋯ Open With has no duplicates", Set(names).count == names.count,
           "\(names.count) entries, \(Set(names).count) unique")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let s = shelf([a]); spin(0.3)
     s.rename(to: "Receipts")
     let named = s.shelf.title == "Receipts"
     s.rename(to: "   ")
     check("Rename API behind the modal item", named && s.shelf.title == nil,
           "set→'Receipts', blank→auto '\(s.shelf.displayTitle)'")
     note("⋯ Rename Shelf…", "not fired: shows a modal NSAlert")
     ShelfStore.shared.closeAll(); spin(0.4) }

do { let delegate = AppDelegate()
     let bar = NSMenu(); bar.delegate = delegate
     delegate.menuNeedsUpdate(bar)
     let n = ShelfStore.shared.controllers.count
     check("menu bar ▸ New Shelf", click(bar, "New Shelf")
           && ShelfStore.shared.controllers.count == n + 1,
           "\(flatten(bar).count) items, shelves \(n)→\(ShelfStore.shared.controllers.count)")
     delegate.menuNeedsUpdate(bar)
     click(bar, "Close All Shelves")
     check("menu bar ▸ Close All Shelves", waitUntil(3) { ShelfStore.shared.controllers.isEmpty },
           "\(ShelfStore.shared.controllers.count) left") }

note("⋯ Open / Reveal / Quick Look / Share / Settings",
     "not fired: would launch apps, open Finder, or show panels")

print("=== MENU DISPATCH RESULTS (via NSApp.sendAction) ===")
let w = results.map(\.0.count).max() ?? 20
for (n, v, d) in results { print("  \(v)  \(n.padding(toLength: w, withPad: " ", startingAt: 0))  \(d)") }
let f = results.filter { $0.1 == "FAIL" }.count
print("\n  \(results.filter { $0.1 == "PASS" }.count) passed, \(f) failed, \(results.filter { $0.1 == "SKIP" }.count) noted")
exit(f == 0 ? 0 : 1)
