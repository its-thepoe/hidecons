# Hidecons

A lightweight macOS menu bar app to hide and show desktop icons instantly.

---

## What it does

Sits in your menu bar as a small grid icon. Left-click hides all desktop icons; left-click again brings them back. Useful for clean screenshots, presentations, focus sessions, or video calls.

- **Outline grid** — icons are visible
- **Filled grid** — icons are hidden
- **Pulsing arrow** — icons are restoring (Finder is reloading)

---

## Install

```bash
git clone https://github.com/alfaruqstories/hidecons.git
cd hidecons
./install.sh
```

The script compiles the Swift source, generates the app icon, builds an app bundle, installs it to `~/Applications/Hidecons.app`, and launches it immediately.

---

## Usage

After launching, a grid icon appears in your menu bar.

| Action | Result |
|---|---|
| **Left click** the icon | Instantly toggles desktop icons |
| **⌥⌘H** from any app | Same toggle — no mouse needed |
| **Right click** the icon | Opens settings menu |
| Hide Widgets with Desktop Icons | Per-user preference, on by default; hides desktop widgets whenever icons are hidden |
| Undo | Reverts the last toggle (appears in menu after any toggle) |
| Launch at Login | Toggles auto-start on login — checkmark = enabled |
| Notify on Toggle | Sends a macOS notification on each hide/show — off by default |
| Report a Bug | Opens GitHub Issues in the browser |
| Quit | Exits — icons stay in their current state |

**State is remembered across reboots.** If icons were hidden when you shut down, they stay hidden on startup. Hidecons reads the current Finder preference on launch and picks up from there.

**Launch at Login** is built into the app — no System Settings or Login Items configuration needed.

---

## Features

- Left-click instant toggle — no menu to open
- Global hotkey ⌥⌘H — toggle from any app
- Undo — single-level revert in the right-click menu
- State remembrance — persists across reboots and restarts
- Restore indicator — icon pulses while Finder reloads the desktop
- Launch at Login — built-in, no System Settings needed
- Haptic feedback on toggle (MacBooks with Force Touch)
- Tooltip showing current state on hover
- Optional toggle notifications via macOS notification centre
- Desktop widget hiding (macOS Sonoma 14 or later, enabled by default)
- Custom app icon — shows correctly in System Settings → Login Items
- Adapts to dark, light, and tinted menu bar themes

---

## How it works

Hidecons writes the Finder preference and, when enabled, the macOS desktop-widget preference:

```bash
defaults write com.apple.finder CreateDesktop -bool false
killall -HUP Finder
```

When “Hide Widgets with Desktop Icons” is enabled, Hidecons also toggles
`com.apple.WindowManager` → `StandardHideWidgets`. The preference is stored per
user and is on by default for new users. Hidecons remembers the previous widget setting and
restores it when desktop icons are shown again.

This is the standard technique used by all desktop-hiding utilities on macOS. Finder picks up the new preference and either stops drawing the desktop or re-renders it.

**Why hiding is instant but restoring takes a moment:** hiding is a single "stop drawing" operation. Restoring requires Finder to re-enumerate all files in `~/Desktop`, generate thumbnails, calculate positions, and render everything. The more files on your desktop, the longer it takes. The pulsing arrow indicator in the menu bar shows when this is in progress.

The preference persists in Finder's own plist — Hidecons writes nothing of its own to disk except a `UserDefaults` key for the notification setting.

---

## Requirements

- macOS 10.15 (Catalina) or later for desktop icons
- macOS 14 (Sonoma) or later for desktop widget hiding
- Xcode Command Line Tools (`xcode-select --install`)

---

## Troubleshooting

**"App is damaged" or "unidentified developer" warning**

The app is not notarised by Apple. To open it anyway:

```bash
xattr -cr ~/Applications/Hidecons.app
```

Or right-click the app → Open → click "Open" in the dialog.

**Icons don't come back after quitting**

Run this in Terminal to restore manually:

```bash
defaults write com.apple.finder CreateDesktop -bool true && killall -HUP Finder
```

---

## License

MIT — fork it, modify it, ship it.
