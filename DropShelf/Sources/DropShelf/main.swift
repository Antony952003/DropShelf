import AppKit

// DropShelf runs as an LSUIElement agent, so there is no storyboard and no
// @main App type — just a plain AppKit entry point.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(Preferences.shared.showInDock ? .regular : .accessory)
application.run()
