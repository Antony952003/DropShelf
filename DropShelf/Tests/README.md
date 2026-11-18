# Tests

Two executable suites. Both drive the app through **`NSApp.sendAction`** — the
same target/action dispatch a real click performs — rather than calling the
handlers directly.

That distinction is the whole point. An earlier version of these tests invoked
`BlockMenuItem.invoke()` directly and reported every menu action as working,
while in the shipped app *nothing in any menu did anything*: the selector had
silently bound to `NSObject.performSelector:`, so clicks threw an exception that
AppKit swallows during menu tracking. A test that skips the integration point
does not test the feature.

- `MenuDispatchTests.swift` — the ⋯ action menu and the menu-bar menu.
- `ControlDispatchTests.swift` — the six settings panes, the shortcut recorder,
  and the card / dropdown controls.

Run them with:

```sh
./run-tests.sh
```

No Xcode or XCTest needed; the runner compiles the app sources together with
each suite using `swiftc`, and runs each in an isolated `HOME` so your real
preferences and saved shelves are never touched.

Actions that would launch another app, open Finder, or show a modal panel are
reported as `SKIP` with the reason, and their wiring is asserted instead.
