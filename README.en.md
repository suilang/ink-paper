# Ink Paper

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md)

> A lightweight, native macOS static wallpaper tool — prefer the system wallpaper API; fall back to a desktop-level overlay when it cannot write.

Ink Paper is built with Swift + AppKit and offers two mutually exclusive modes: set the system desktop wallpaper when possible; when the system wallpaper is unwritable or locked, place a full-screen window behind the desktop icons to act as wallpaper visually. v1 supports local static images only, lives in the menu bar, and uses one window per display.

---

## Why this exists

Changing a wallpaper should be simple, but on macOS it often is not:

- **System wallpaper cannot be written** — on managed devices, with configuration profiles, or under permission / system-state issues, many tools only error out or fail silently.
- **“Fake wallpaper” windows steal interaction** — covering the desktop with a normal window can block the Dock, menu bar, or desktop icon clicks.
- **Multi-display setups break** — after plugging / unplugging external displays or changing resolution, overlays misalign or only cover the main screen.

Ink Paper is built for that:

1. **Prefer the system when it works** (Mode A); degrade to a desktop-level overlay (Mode B) when Mode A fails or is unavailable. Modes are mutually exclusive; switches are transactional and can roll back.
2. **Overlay does not steal interaction** — never becomes key, click-through, desktop-level stacking so Dock / menu bar / desktop icons stay usable.
3. **One window per display**, rebuilt on screen connect / disconnect and resolution changes.
4. **Native and performance-first** — config persists locally and restores on launch; failures surface actionable messages instead of failing silently.

---

## What you can do

| Feature | Description |
|---------|-------------|
| **System wallpaper mode** | Set / read macOS system static wallpapers |
| **Overlay wallpaper mode** | Full-screen desktop-level image windows when the system is unwritable |
| **Auto / manual mode** | Health checks recommend a mode; you can also force one |
| **Multi-display** | One image for all screens, or a different image per display |
| **Scale modes** | fill / fit / stretch / center |
| **Menu bar entry** | Always-on menu bar control for picking images and toggling |
| **Launch at login** | Optionally start at login and restore the last wallpaper state |

> Out of scope for this release: video / dynamic / web wallpapers, Windows / Linux, online galleries, scheduled multi-image rotation, and similar. See the [technical requirements](docs/technical-requirements.md).

---

## Download & install

Grab a `.dmg` or `.zip` from [Releases](https://github.com/suilang/ink-paper/releases) and drag `InkPaper.app` into Applications.

Current builds are **not Apple Developer signed / notarized**. On first open, Gatekeeper may block the app — use any of these:

1. **Right-click Open**: right-click the app → **Open** → confirm (do not double-click).
2. **System Settings**: after a blocked open, go to **System Settings → Privacy & Security** → **Open Anyway**.
3. **Unquarantine script**:

```bash
# Defaults to /Applications/InkPaper.app
curl -fsSL https://raw.githubusercontent.com/suilang/ink-paper/main/scripts/unquarantine.sh | bash

# Or run from a clone; optional App / DMG path
./scripts/unquarantine.sh
./scripts/unquarantine.sh /Applications/InkPaper.app
./scripts/unquarantine.sh ~/Downloads/InkPaper-v0.2.0-macos.dmg
```

If it is still blocked, use step 1 or 2.

---

## Sponsor

If this project helps you, feel free to buy the author a milk tea.

<p align="center">
  <img src="docs/assets/wechat-pay.png" width="180" alt="WeChat Pay QR code" />
</p>

Sponsorships are used only for maintaining and developing this project.

---

## Open the project

```bash
open InkPaper.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -scheme InkPaper -project InkPaper.xcodeproj \
  -configuration Debug \
  -derivedDataPath .derivedData build
```

- Minimum OS: macOS 13.0
- Bundle ID: `com.ink.InkPaper`

---

## Docs

| Doc | Description |
|-----|-------------|
| [docs/technical-requirements.md](docs/technical-requirements.md) | Product constraints and implementation guidance |
| [docs/impl/README.md](docs/impl/README.md) | Current code behavior by module (Chinese) |

---

## License

This repository is licensed under the [MIT License](LICENSE).

You may use, modify, and distribute freely, provided you retain the copyright and permission notice. The software is provided “as is”, without warranty of any kind.
