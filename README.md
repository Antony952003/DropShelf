# dropover-rebuild

A REA-driven analysis of the shipped **Dropover 5.0.3** app bundle, and
**DropShelf** — a working, clean-room macOS drag-and-drop shelf built from that
analysis.

```
dropover-rebuild/
├── ANALYSIS.md                  REA findings → rebuild specification
├── INSTALL.md                   install + release instructions
├── LICENSE                      MIT
└── DropShelf/
    ├── build.sh                 build + bundle + ad-hoc sign
    ├── package-release.sh       universal build, verified + zipped
    ├── run-tests.sh             compile + run both dispatch suites
    ├── Tests/                   regression suites (see Tests/README.md)
    ├── Package.swift
    ├── Resources/Info.plist
    ├── Tools/make-icon.swift    draws the app icon (no bundled artwork)
    └── Sources/DropShelf/       ~5,500 lines of Swift / AppKit
```

## Install

**Just want to use it?** Download `DropShelf.zip` from
[Releases](../../releases) and follow [INSTALL.md](INSTALL.md) — it is a
universal build (Apple Silicon + Intel), and there is one Terminal command to
run because the app is not notarised.

**Build it yourself** — needs only the Swift toolchain from Command Line Tools,
no Xcode, no `xcodebuild`, no third-party packages:

```sh
cd DropShelf
./build.sh                      # native arch
UNIVERSAL=1 ./build.sh          # arm64 + x86_64
./package-release.sh 1.0        # universal + zipped for sharing
open build/DropShelf.app
```

DropShelf is an `LSUIElement` agent: it has no Dock icon by default, just a
menu-bar tray item. Verified on macOS 26.7.1 (arm64) with Swift 6.4.

### Permissions

| Works immediately | Needs Accessibility |
| --- | --- |
| menu bar, global hotkeys (Carbon), `dropshelf://` URLs, Services item, all shelf UI, drag in and out, Quick Look, action menu, settings | shake-to-activate, modifier-key activation, hover-scoped shelf shortcuts, **and the notch/top-edge drop target** |

The notch target is on that second list because it only shows itself while a
drag is in flight, and detecting that uses the same system-wide mouse monitor
as the shake gesture.

Accessibility is requested once on first launch. Because `build.sh` signs
ad-hoc, **rebuilding changes the code hash and the grant must be re-approved.**

## What it does

| Area | Behaviour |
| --- | --- |
| Activation | shake while dragging (3 sensitivities) · hold ⌘/⌃/⇧ while dragging · drop onto the MacBook notch (3 highlight modes; top-centre strip on Macs without one) · global hotkeys · menu bar · `dropshelf://new`, `dropshelf://clipboard` · "Add to DropShelf" Services item |
| Shelf window | borderless non-activating floating panels with hairline edges · rename via the action menu · icon/list bodies in the dropdown · colour stripe per shelf · item count and total size · pin · all-Spaces or current-Space only |
| Content | files, folders, web URLs, plain text, RTF, images · de-duplicated by path · unresolvable items pruned on reopen |
| Drag out | real files hand over their URL so the destination performs the move or copy · images use a file promise, so Finder gets a real `.png` · text goes out as text · move by default, copy with the preference on, system downgrades to copy across volumes |
| Placement | snap to screen edges and other shelves on release, ⌘ defeats it · dock to left/right edge with a hover peek · double-click edges to dock / move aside / nothing · cascade so stacked shelves never land on top of each other |
| Presentation | the shelf is a fixed 184×206 **card**: colour stripe, large circled ✕ (top-left) and ⋯ (top-right), the items as a fanned pile, and an "N Files ⌄" pill. The pill opens a **separate dropdown panel** beneath the card — a real child window, 340pt wide, so it tracks the card — holding ⚙ · "N Items · size" · grid/list toggle, then the file rows. The card never resizes. Toggle with the pill (its chevron flips), ⌘E, or the action menu. **Geometry only ever changes on a click, never on hover.** |
| Motion | every control is a `SpringButton`: swells under the pointer, squashes on press, settles on a `CASpringAnimation` — stiffer while pressed, looser with overshoot on release · pointing-hand cursor · the card pops in from 95% · the dropdown unfolds downward · the pile pulses when content lands · scaling uses a centred `CATransform3D`, not the layer `anchorPoint`, which AppKit resets during layout |
| Card chrome | measured off the reference: 184×194 card, 20pt corners, 24pt ✕ / ⋯ discs inset 9pt with medium-weight glyphs, a 30×4 centred colour pill at the top (not a full-width stripe), and an 89×24 bottom capsule whose chevron sits in its own 18pt disc. Discs and capsules are drawn as inscribed ovals in `draw(_:)`, so they stay circular at any size — `layer.cornerRadius` from an initial frame does not |
| Wording | the capsule names the content: "2 Images", "1 Folder", "3 Videos", falling back to "Files" for a mixed shelf |
| Move aside | after the first drop the shelf glides to the top-right of its screen, 12pt from each edge, keeping its presentation · multiple parked shelves stack downwards · dragging it by hand un-parks it · snapping is suppressed while parked so the margin survives · on by default |
| Actions | Open · Open With · Reveal in Finder · Quick Look · Copy · Add From Clipboard · Compress (via `ditto`) · Share sheet · Move/Show in New Shelf · Remove · Clear · Pin · View As · Close |
| Shortcuts | 5 recordable global actions with conflict and system-collision validation · 11 shelf shortcuts live on hover (consumed via an event tap so they don't leak to the frontmost app) |
| Screenshots | new screenshots land on a shelf automatically, titled "Screenshots" · reads `com.apple.screencapture location` rather than assuming the Desktop · two detectors de-duplicated by path: a Spotlight `NSMetadataQuery` on `kMDItemIsScreenCapture` (filename-language and location independent) and a `DispatchSource` watch on the folder (works with Spotlight indexing off) · shots within 90s group onto one shelf · on by default |
| Persistence | pinned shelves reopen on launch, the rest become Recent Shelves (⌥-click to remove one) · reopen last closed |
| Settings | 6 AppKit panes: General, Activation, Shelf, Shortcuts, Ignored Apps, About · launch at login via `SMAppService` · Show in Dock · menu-bar icon style · ignored-applications list |

## What it does not do

Cloud sharing (Dropover Cloud, S3, Dropbox, Google Drive, OneDrive, Imgur,
iCloud links) and upload history · in-app purchases · widget · share extension ·
App Intents / Shortcuts · folder monitoring · Instant Actions · user-script
Custom Actions · Alfred / Raycast installers · localisation beyond English.

Cloud sharing is the single largest omission — 57 of Dropover's 516 localised
strings. Each provider needs a paid account and a server; the action menu's
extension point for them is `cloudProviderMenuItems(for:)` in
`ShelfActions.swift`, which deliberately returns `[]` rather than showing dead
entries.

## Provenance and licensing

Dropover is a paid, closed-source app by Damir Tursunović, and "Dropover" is
his product name — DropShelf is an independent reimplementation, not affiliated
with or endorsed by him. This repository contains **no Dropover code, artwork,
nibs, strings, or other resources.** The raw REA evidence export is
`.gitignore`d for the same reason: it holds data read out of a commercial
binary. Regenerate it locally if you want it.

`ANALYSIS.md` records only facts recoverable from the shipped bundle's
metadata: `Info.plist`, Mach-O load commands, compiled Interface Builder object
graphs, and localisation tables. No disassembler provider (Ghidra / Hopper /
IDA / Kuna) was configured on the analysis host, so **nothing was decompiled and
no function body was read.** DropShelf is original Swift written against the
public AppKit SDK, reproducing observed *behaviour*; the icon is drawn by
`Tools/make-icon.swift` and every other glyph is an SF Symbol.

## Tests

```sh
cd DropShelf && ./run-tests.sh
```

Two suites, 31 assertions, driven through **`NSApp.sendAction`** — the dispatch
path a real click takes, not the handlers directly. That distinction is the
point: an earlier version called the closures directly and reported every menu
action green while, in the shipped app, *nothing in any menu did anything*.
See [Tests/README.md](DropShelf/Tests/README.md).

No Xcode or XCTest needed, and each suite runs in an isolated `HOME` so real
preferences and saved shelves are untouched.

## Verification performed

Checked by running the built app, not just by compiling it:

- launches and idles at 0% CPU / ~44 MB
- `dropshelf://clipboard` builds a shelf from clipboard text and from multiple
  file URLs — all items land, with correct payload types
- shelf windows confirmed on screen via `CGWindowListCopyWindowInfo`: floating
  window level 3, 320×240, opaque
- 14 stacked shelves all received distinct positions, exercising both the
  down-right cascade and the up-right fallback when the Dock pins the floor
- buttons pixel-probed by rendering them offscreen: the 24pt disc's filled area
  is 1.01× a perfect circle of the same diameter (a square would be 1.27×), the
  capsule's corners are fully transparent, and its chevron knob is present at
  the trailing end
- writing a PNG into the real screenshot folder produced a shelf titled
  "Screenshots"; a second one 4s later grouped into the same shelf (1 window,
  2 items) rather than spawning a second card
- shelves round-trip through `~/Library/Application Support/DropShelf/shelves.json`
- expanding produces two windows: a 184×206 card and a 340pt-wide dropdown 6pt
  below it with left edges aligned, the dropdown's height fitted to its rows
- a new shelf opens as the 184×206 pile card, glides to exactly 12pt from the
  top and right of its host screen's `visibleFrame`, and is then byte-identical
  3s later — no oscillation, no snap stealing the margin (measured via
  `CGWindowListCopyWindowInfo` on a two-display setup)
- no exceptions or AppKit asserts in the unified log

Bugs found and fixed this way: the unnamed-shelf placeholder was being persisted
as a literal title; dragging a shelf by its own window could trigger the shake
gesture; `isMovableByWindowBackground` made the window steal every drag that
started on an item, so content could not be dragged out at all; retract
collapsed the shelf in place instead of moving it aside as Dropover's own
preference text describes; hover-driven expansion oscillated, because growing
the window moved its edge out from under the pointer and fired another exit;
snapping fired after the park animation and pulled the card flush to the screen
edge; expanding destroyed the only control that could collapse it again; and a
pinned shelf restored in the expanded state never built its dropdown, because
the refresh path only repositioned an existing one.

- every ⋯ menu action, the menu-bar menu, all six settings panes, the shortcut
  recorder, and the card/dropdown controls dispatch correctly (31 assertions,
  0 failures)

Not exercised at runtime (needs real input devices, a notched display, or
granted permissions): shake and modifier-key gestures, the notch target,
drag-out move/copy against Finder, Quick Look, the hover-shortcut event tap, the
settings panes, and the appearance of the drawn UI — this host denies screen
recording, so no screenshot could be taken of the shelf or the parked card.
