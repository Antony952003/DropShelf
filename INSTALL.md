# Installing DropShelf

Two ways. **Option A** is the one to send friends.

Requires macOS 13 (Ventura) or later. The download is a universal binary, so it
runs on both Apple Silicon and Intel Macs.

---

## Option A — download the app

1. Go to the repository's **[Releases](../../releases)** page and download
   `DropShelf.zip`.
2. Double-click the zip, then drag **DropShelf.app** into `/Applications`.
3. **Clear the quarantine flag.** macOS blocks apps downloaded from the web
   unless they are notarised by a paid Apple Developer account, which this is
   not. Open Terminal and run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/DropShelf.app
   ```

4. Launch it from Applications.

If you skip step 3 you will get **"DropShelf is damaged and can't be opened"**
or **"cannot be opened because the developer cannot be verified"**. That message
is Gatekeeper reacting to the missing notarisation, not to anything wrong with
the app. The alternative to the Terminal command is: right-click the app ▸
**Open** ▸ **Open** in the dialog, or allow it under System Settings ▸ Privacy &
Security after the first blocked attempt.

> Only run that command on software you actually trust. It is the standard step
> for any unnotarised Mac app, but it does switch off a real safety check.

### There is no icon in the Dock

By design — DropShelf is a menu-bar app. Look for a **tray icon** in the menu
bar. If your menu bar is full it may be hidden; to get a Dock icon instead, open
Settings ▸ General ▸ **Show in Dock**, or run:

```sh
open -g "dropshelf://dock"
```

### Grant Accessibility access

Most things work immediately. These four need permission, because they read
input system-wide:

- shake-to-activate
- modifier-key activation
- shelf shortcuts while hovering
- the notch / top-edge drop target

DropShelf asks on first launch. To do it later: **Settings ▸ Activation ▸
Grant…**, or System Settings ▸ Privacy & Security ▸ Accessibility.

Screenshots live in a protected folder on many setups, so macOS may also ask for
**Desktop** or **Documents** access the first time a screenshot is picked up.

---

## Option B — build from source

No Xcode needed, just the Command Line Tools.

```sh
xcode-select --install          # if you don't already have it
git clone https://github.com/Antony952003/DropShelf.git
cd DropShelf/DropShelf
./build.sh
open build/DropShelf.app
```

Building locally has a nice side effect: the app is signed on your own machine,
so there is no quarantine flag and no Gatekeeper prompt.

---

## Publishing a release (maintainer)

```sh
cd DropShelf
./package-release.sh 1.0        # -> build/DropShelf-1.0.zip, universal
```

Then create a release and attach the zip:

```sh
gh release create v1.0 build/DropShelf-1.0.zip \
  --title "DropShelf 1.0" \
  --notes "First release. See INSTALL.md — the quarantine flag must be cleared."
```

`package-release.sh` uses `ditto`, not `zip`, because `zip` can mangle a `.app`
bundle's symlinks and break its signature. It verifies the signature before
packaging.

### Why isn't it notarised?

Notarisation requires an Apple Developer Program membership (US$99/year). With
one, the flow would be: sign with a Developer ID certificate, `notarytool
submit --wait`, `stapler staple`, and then the app would open with no warning
and no Terminal command. Without one, ad-hoc signing plus the quarantine step is
the honest best option.

---

## Uninstalling

```sh
rm -rf /Applications/DropShelf.app
rm -rf ~/Library/Application\ Support/DropShelf
defaults delete local.dropshelf.app
```

Also remove DropShelf from System Settings ▸ Privacy & Security ▸ Accessibility
if you granted it.
