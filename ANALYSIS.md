# Dropover 5.0.3 — REA analysis → rebuild specification

Target: `/Applications/Dropover.app` (Mac App Store build)
Executable SHA-256: `faf16dc3d77b6bff739d218e8107ec71744cb18d5c39814a201c443627784138`
Evidence bundle: `evidence/dropover-evidence.json` (6 records, 0 unresolved unknowns)

All statements below are **observations** from the shipped artifact unless marked
*inference*. No disassembler provider (Ghidra / Hopper / IDA / Kuna) was configured on
this host, so **no decompilation was performed and no function bodies were read**.
Everything here comes from Mach-O load commands, the Info.plist, compiled Interface
Builder archives, and the localization tables.

---

## 1. Bundle identity (observed — `inspect_plist`)

| Fact | Value |
| --- | --- |
| Bundle ID | `me.damir.dropover-mac` |
| Version | 5.0.3 (build 460) |
| Min system | macOS 13.0 |
| UI mode | `LSUIElement = true` — menu-bar agent, no Dock icon by default |
| Principal class | `DropoverApplication` (NSApplication subclass) |
| Main UI | `NSMainStoryboardFile = Main` (AppKit storyboard, not SwiftUI lifecycle) |
| URL schemes | `dropover` (own), plus Dropbox / Google / OneDrive OAuth callbacks |
| Services menu | `addToDropoverService` — accepts string, file-contents, RTF, RTFD, URL |
| App Intents | `AddToShelfIntent`, `CreateCloudSessionIntent`, `GetFilesFromShelfIntent`, `OpenRecentShelfIntent` |
| Document types | `public.data`, extension `*`, role Viewer, `LSHandlerRank = None` |
| iCloud | Ubiquity container `iCloud.me.damir.dropover-mac`, public document scope |
| Receipt | `_MASReceipt` present → Mac App Store distribution |

## 2. Linkage (observed — `inspect_macho`, 60 dependencies, exhaustive)

Universal binary (`x86_64` + `arm64`), 78 load commands, 5 segments, 2754 imports.

Private frameworks shipped in the bundle:
`DropoverCore`, `DropoverFileOperations`, `DropoverCloud`, `DropoverAWS`,
`GoogleDrive`, `MicrosoftOneDrive`.

System frameworks that pin down the implementation technique:

| Framework | What it implies (*inference*) |
| --- | --- |
| `AppKit` + `Carbon` | AppKit windows; Carbon `RegisterEventHotKey` for global shortcuts |
| `QuickLookUI` | in-shelf Quick Look preview panel |
| `PDFKit`, `ImageIO`, `AVFoundation`/`AVKit` | thumbnailing + the bundled `intro_*.mov` onboarding videos |
| `ServiceManagement` | launch-at-login via `SMAppService` |
| `StoreKit` | in-app "Dropover Pro" purchase |
| `Intents` | the four App Intents above |
| `WidgetKit` | `RecentShelvesWidgetExtension.appex` |
| `SwiftUI` | newer settings panes only (storyboard is still the main UI) |
| `Combine`, `swift_Concurrency` | reactive state + async upload pipeline |
| `Security`, `SystemConfiguration` | Keychain for cloud creds, reachability |

Extensions: `DropoverShareExtension.appex`, `RecentShelvesWidgetExtension.appex`.

## 3. Object model (observed — `decode_interface_builder`)

18 compiled IB documents, 1666 graph nodes, 18 view controllers, 44 wired actions,
92 outlets. Mangled Swift class names decode as:

**Main app (`Dropover` module)**

- `DragSessionOutlineViewController` — the shelf's chrome. Outlets: `titleTextField`,
  `segmentedControl`, `barButton`, `separator`, `contentView`.
  → *inference*: the shelf is a container; the segmented control swaps the body
  controller, `contentView` hosts it, `titleTextField` is the editable shelf name.
- `DragSessionGridViewController` — icon body (`view` outlet only → built in code).
- `DragSessionListViewController` — list body. Outlets: `tableView`, `scrollView`,
  `clipView`, `progressIndicator` → `NSTableView` in a scroll view.
- `DragSessionListItemCellView` — the list row view.
- `PageWindowController` + `PageContainerViewController` + `PageControl` — the
  onboarding / "Quick Start Guide" pager.
- `PopoverTextContentViewController`, `PopoverScrollableTextContentViewController` —
  text-item preview popovers.
- `S3ConfigurationViewController`, `S3UploadOptionsConfigurationViewController`,
  `IgnoredApplicationsViewController`, `ApplicationDataViewController`,
  `DiagnosticsClearDataViewController` — settings sheets.
- `HoverableButton`, `HighlightableButton` — custom hover-tracking controls.

**`DropoverFileOperations` framework**: `ApplicationScriptsViewController`,
`ApplicationScriptEditViewController`, `ApplicationScriptOperationTestViewController`,
`ApplicationScriptsIntroductionViewController` → the user-script ("Custom Actions")
editor, with a test harness.

Menu actions wired in `MainMenu.nib` (observed selectors):
`didSelectNewShelfMenuItem:`, `didSelectPreferencesMenuItem:`,
`didSelectPurchasesMenuItem:`, `didSelectQuickStartGuideMenuItem:`,
`didSelectWebsiteMenuItem:`, `showAboutWindow:`.

## 4. Feature surface (observed — 516 keys in `en.lproj/Localizable.strings`)

Key namespaces by size: `preferences` (81), `service` (57),
`directory-observation` (38), `action` (32), `menu` (27), `page` (15),
`purchases` (15), `keyboard-action` (14), `content` (11), `outline` (8).

### Shelf activation (`preferences.shelf.*`)
- Shake gesture while dragging, with 3 sensitivity levels
  (`normal` / `high` / `ludicrous`).
- Hold a modifier key while dragging — ⌘, ⌃, or ⇧.
- Drop onto the MacBook **notch**, with three highlight modes
  (`always-highlight`, `hover-highlight`, `never-highlight`).
- Global keyboard shortcuts.

### Shelf behaviour (`preferences.*`)
`Snap into place` (hold ⌘ to defeat) · `Automatically retract` after the first drop ·
`Dock to Edge` · `Double-click shelf edges` → Dock / Retract / Nothing ·
`Close shelf after dragging` · `Copy files instead of moving` (default is **move**,
unless cross-volume) · `Convert text to plain text` (default keeps formatting) ·
`Restrict to current Space` (default: all Spaces) · `Use color to differentiate
shelves` · menu-bar icon style (Traditional / Document / Document 2) ·
`Show in Dock` · `Show in menu bar` · `Launch at login` · ignored-applications
list · screenshot shelf · `Disable Dropover online features`.

### Shelf shortcuts (`keyboard-action.*`) — active while hovering a shelf
New Shelf · New Clipboard Shelf · Reopen Last Closed Shelf · Close · Close All
Shelves · Clear Shelf Content · Copy Shelf Content · Paste · Quick Look ·
Open Action Menu · Open Command Bar · Dock to Left/Right Edge · Toggle Docking
for All Shelves.

### Item actions (`action.*`)
Open · Open With · Reveal in Finder · Copy · Compress (zip) · Add From Clipboard ·
Clear Shelf · Move to New Shelf · Show in New Shelf · Dock to Edge · Settings.
Cloud link actions: Dropover Cloud, iCloud, Imgur, AWS S3, Dropbox, Google Drive,
OneDrive — each with an upload-progress UI and a share history
(`menu.item.share-history.*`: Copy Link, Open in Browser, Delete & Revoke).

### Other panes
`Instant Actions` (actions shown on an empty shelf, 7 categories) ·
`Folder Monitoring` (`directory-observation`, 38 keys) · `Custom Actions`
(user scripts in the Application Scripts folder) · `Dropover Pro` (StoreKit) ·
Alfred workflow + Raycast extension installers (`Add to Dropover.alfredworkflow`
is shipped in Resources).

---

## 5. What this rebuild implements

`DropShelf/` is a **clean-room reimplementation**: original Swift written against the
public AppKit SDK, reproducing the *behaviour* catalogued above. No Dropover code,
decompiled output, artwork, or resource was copied — icons come from SF Symbols, and
the UI is rebuilt in code rather than from Dropover's nibs.

**Built (working):**
shelf windows as non-activating floating panels · shake-to-activate with 3
sensitivities · modifier-key activation · notch / top-edge drop target with the three
highlight modes · global hotkeys via Carbon · grid + list bodies with a segmented
switch · editable shelf titles · colour labels · drop of files, text, images and URLs ·
drag-out with move-vs-copy semantics and file promises for synthesised items · Quick
Look · action menu (Open, Open With, Reveal, Copy, Compress, Share, Move/Show in New
Shelf, Delete, Clear) · snapping with ⌘ defeat · edge docking · auto-retract ·
double-click-edge behaviour · close-after-drag · hover-scoped shelf shortcuts ·
menu-bar item with Recent Shelves and Pinned Shelves · reopen last closed shelf ·
clipboard shelf · launch at login via `SMAppService` · Show in Dock toggle ·
ignored-applications list · settings window · JSON persistence of shelves.

**Deliberately out of scope** (each needs a paid account, server, or Apple entitlement
this rebuild has no access to):
cloud providers (Dropover Cloud, S3, Dropbox, Google Drive, OneDrive, Imgur, iCloud
links) and their share history · StoreKit "Pro" purchase · WidgetKit widget · Share
extension · App Intents / Shortcuts · folder monitoring (`directory-observation`) ·
screenshot shelf · Instant Actions · user-script Custom Actions · Alfred / Raycast
installers · onboarding videos · localisation beyond English.

Cloud sharing is the largest omission by string count (57 `service.*` keys); the
action-menu architecture in `ShelfActions.swift` has the extension point where a
provider would attach.
