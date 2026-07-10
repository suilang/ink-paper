# Ink Paper Technical Requirements

> Role: global constraints and implementation guidance. No real code; not bound to specific API call details.  
> Scope: macOS static wallpaper tool (Swift + AppKit).  
> Version: v0.1 (draft)

---

## 1. Product goals

Ink Paper is a macOS wallpaper tool with two mutually exclusive run modes:

| Mode | Name | Goal |
|------|------|------|
| A | System wallpaper mode | Read/write and control the macOS system desktop wallpaper directly |
| B | Overlay window mode | When the system wallpaper is unwritable / locked, place a native full-screen window at the desktop level to act as wallpaper visually |

v1 supports **static images** only. Performance first; native Swift + AppKit.

---

## 2. Design principles

1. **Prefer the system when it works**: Mode A by default; enter Mode B only when Mode A is unavailable or the user explicitly chooses it.
2. **Modes are mutually exclusive**: Only one mode may be active at a time; switching must fully clean up the other mode’s side effects.
3. **One window per display**: In Mode B, each display gets its own overlay window; never stretch a single window across displays.
4. **Do not steal interaction**: Overlay windows must not become key, must not receive mouse/keyboard, and must not block normal interaction with the Dock, menu bar, or desktop icons.
5. **Config is restorable**: Persist all user choices; on launch, restore the last state from config.
6. **Failures are visible**: Any set failure must include a clear reason and actionable guidance; silent failure is forbidden.
7. **Minimal permissions**: Request only what is needed; do not request unrelated TCC permissions.

---

## 3. Scope boundaries

### 3.1 In scope for this release

- Mode A: set / read system static wallpaper
- Mode B: multi-display desktop-level full-screen static image windows
- Automatic mode detection and manual switching
- Local image selection and path memory
- Basic preferences / settings UI
- Launch / quit / login-item basics
- Rebuild windows on display plug/unplug and resolution changes
- Status and health checks
- Menu bar presence (recommended)

### 3.2 Out of scope for this release

- Video wallpaper, dynamic wallpaper, web wallpaper, shader / particle effects
- Windows / Linux
- iCloud / online gallery sync
- Wallpaper store / online download
- Multi-image slideshow / scheduled rotation (config keys may be reserved; no scheduler this release)
- Lock-screen wallpaper control
- Changing Dock, menu bar, or desktop icon layout
- Screen saver
- Remote control / multi-user session sync

### 3.3 Hard constraints

- **Do not inset around Dock / menu bar**: Mode B windows fill the screen `frame`; because they sit at the desktop level, Dock and menu bar naturally draw above them—no safe-area cropping.
- **Do not block desktop icon interaction**: Window level must be below the desktop-icon layer or correctly cooperate with the desktop layer so Finder desktop icons remain clickable.
- **Static images only**: Common local formats (suggested: JPEG, PNG, HEIC, TIFF, BMP, WebP—whatever the system can decode).
- **Current user session only**: Operate on the current login user’s desktop space; do not handle complex Fast User Switching sync.

---

## 4. Run modes in detail

### 4.1 Mode A: System wallpaper mode

**Responsibilities**

- Set the user-selected static image as the system desktop wallpaper for specified display(s) or all displays
- Read the current system wallpaper path / identifier when the system allows
- Default recommended mode when writable

**Behavior**

- Support “same image on all displays” and “per-display images” (config-controlled)
- On success, update local state cache
- On failure, record the reason and offer / prompt fallback to Mode B

**Exit / switch cleanup**

- Before switching to Mode B: do not force-restore the user’s previous system wallpaper (optional “backup before switch and allow restore”)
- On app quit: keep the system wallpaper that was set (system wallpaper is not an app-owned resource)

### 4.2 Mode B: Overlay window mode

**Responsibilities**

- On each available screen, create a borderless, full-screen, inactive, non-interactive native window
- Window content is a static image (scale mode configurable)
- Place windows at the desktop level to simulate wallpaper

**Behavior**

- One window per screen; window frame = corresponding `NSScreen.frame` (full-screen coordinates including the menu bar region)
- Window set grows / shrinks / moves / resizes with screen configuration changes
- On launch, if configured for Mode B, create overlays automatically
- On quit, destroy all overlay windows

**Window constraints (hard)**

| Item | Requirement |
|------|-------------|
| Border | Borderless |
| Title bar | None |
| Can become key | No |
| Can become main | No |
| Mouse events | Ignored (click-through to the desktop below) |
| Collection behavior | Appear on all Spaces (configurable); not in window cycle |
| Level | Desktop level (below normal windows and Dock) |
| Cover Dock | Not allowed (enforced by level, not by geometry insets) |

### 4.3 Mode selection strategy

Suggested priority:

1. User-locked mode (if “force a specific mode” is on)
2. Health-check result: Mode A writable → recommend / auto use A; not writable → auto or prompt B
3. Last successfully running mode

Switching must be transactional: stop old mode → validate → start new mode → on failure, roll back and report error.

---

## 5. Multi-display rules

1. The current system `NSScreen` list is the single source of truth.
2. Screen IDs must map stably to config (prefer a stable screen identifier; if unavailable, fall back to arrangement index and prompt the user to reconfirm per-display images on change).
3. React to:
   - Screen connect / disconnect
   - Main display change
   - Resolution / scale-factor change
   - Screen arrangement change
4. Mode A: call system wallpaper set for each target screen per config.
5. Mode B: ensure exactly one live window per screen; destroy extras, create missing, update frame and content on change.
6. After external display sleep / wake, re-validate window visibility and content once.

---

## 6. Image and rendering constraints

### 6.1 Input

- Source: local files (file picker / drag onto settings)
- Validate: exists, readable, decodable, within size limits
- Suggested limits (configurable): file ≤ 50MB; edge ≤ 16384px (reject or suggest compression; this release defaults to reject with a clear reason)

### 6.2 Scale modes (config)

| Mode | Meaning |
|------|---------|
| fill | Scale to cover; may crop |
| fit | Scale to fit entirely; may letterbox |
| stretch | Stretch to fill; does not preserve aspect |
| center | Center at native size; no scale (crop if larger) |

Default: `fill` (closest to typical system wallpaper look).

### 6.3 Letterbox color

When mode is `fit`, background fill color is configurable (default black).

### 6.4 Caching

- May keep an in-memory cache of decoded bitmaps sized per screen to avoid frequent redraw
- Invalidate on screen parameter changes
- Disk cache not required (optional this release)

---

## 7. Configuration keys

Persistence suggestion: `UserDefaults` or JSON/plist under Application Support. Sensitive paths stay local only.

### 7.1 General

| Key (logical) | Type | Default | Description |
|---------------|------|---------|-------------|
| `app.launchAtLogin` | Bool | false | Launch at login |
| `app.showMenuBarExtra` | Bool | true | Show menu bar icon |
| `app.openConfigOnLaunch` | Bool | false | Open settings on launch |
| `app.language` | String | system | Language (reserved; may follow system this release) |
| `app.lastMode` | Enum(A/B) | A | Last mode |
| `app.preferredMode` | Enum(auto/A/B) | auto | Preferred: auto / force A / force B |
| `app.backupSystemWallpaperBeforeSwitch` | Bool | true | Backup system wallpaper info before mode switch |

### 7.2 Mode and wallpaper

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `wallpaper.imagePath` | String? | nil | Global default image path (when shared across displays) |
| `wallpaper.perDisplayEnabled` | Bool | false | Per-display images |
| `wallpaper.perDisplayMap` | Map<DisplayID, Path> | {} | Per-display image map |
| `wallpaper.scaleMode` | Enum | fill | Scale mode |
| `wallpaper.fitBackgroundColor` | Color | black | Letterbox color for fit |
| `wallpaper.applyToAllSpaces` | Bool | true | Whether Mode B is visible on all Spaces |

### 7.3 Mode B windows

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `overlay.enabled` | Bool | false | Whether overlay mode is active (driven by mode engine; usually read-only status) |
| `overlay.ignoreMouseEvents` | Bool | true | Must be true (hard constraint; settings may show but not disable) |
| `overlay.restoreOnDisplayChange` | Bool | true | Rebuild automatically after display changes |
| `overlay.hideOnAppQuit` | Bool | true | Destroy windows on quit (hard constraint; prefer locked to true) |

### 7.4 Health and diagnostics

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `health.checkOnLaunch` | Bool | true | Run health check on launch |
| `health.autoFallbackToOverlay` | Bool | true | Auto fall back to B when Mode A fails |
| `health.notifyOnFallback` | Bool | true | Notify user on fallback |
| `health.lastCheckAt` | Date? | nil | Last check time |
| `health.lastCheckReport` | Object | {} | Last check summary |

### 7.5 Reserved (UI may hide this release)

| Key | Description |
|-----|-------------|
| `wallpaper.slideshowEnabled` | Slideshow toggle (not implemented) |
| `wallpaper.slideshowIntervalSec` | Slideshow interval |
| `wallpaper.videoEnabled` | Video wallpaper (not implemented) |

---

## 8. Health / preflight checks

Checks run as: **on launch**, **before switch**, and **scheduled / manual diagnostics**. Result levels: `pass` / `warn` / `fail`.

### 8.1 Environment

| ID | Check | Failure impact |
|----|-------|----------------|
| E01 | OS version in supported range (suggest macOS 13+; final = deployment target) | May not run |
| E02 | GUI login session (not pure SSH / headless) | Cannot overlay / set wallpaper |
| E03 | Screen list non-empty | Cannot apply |
| E04 | App has needed filesystem read access (selected image readable) | Cannot load image |

### 8.2 Mode A writability

| ID | Check | Notes |
|----|-------|-------|
| A01 | System desktop image API callable | Baseline capability |
| A02 | Whether MDM / configuration profile locks the desktop | If locked, Mode A unavailable |
| A03 | Probe write (optional): set and read back on a temp / current screen, then restore | Most reliable; avoid flicker; may be a “deep check” |
| A04 | Target image meets system set requirements | Path, format |

### 8.3 Mode B availability

| ID | Check | Notes |
|----|-------|-------|
| B01 | Can create a window at the required level | Core |
| B02 | Window below normal app windows and does not cover Dock | Visual / level acceptance |
| B03 | Clicks pass through to the desktop | Interaction acceptance |
| B04 | Window count equals screen count on multi-display | Consistency |
| B05 | After Space switch, windows remain visible per config | If all-Spaces is on |

### 8.4 Resources

| ID | Check | Notes |
|----|-------|-------|
| R01 | Configured image path exists | |
| R02 | File readable | |
| R03 | Decodable as bitmap | |
| R04 | Within size / dimension limits | |
| R05 | In per-display mode, every enabled screen has a valid image (or can fall back to global) | |

### 8.5 State consistency

| ID | Check | Notes |
|----|-------|-------|
| S01 | `preferredMode` matches actual running mode | |
| S02 | Modes A/B mutually exclusive (no dual leftovers) | |
| S03 | Mode B window list in sync with screen list | |
| S04 | Backed-up system wallpaper info restorable (if backup enabled) | |

Reports must be viewable in Settings → Diagnostics, with “Copy report” for feedback.

---

## 9. Settings UI guidance

### 9.1 Entry points

- Menu bar icon → “Settings…”
- App menu → “Settings…”
- Shortcut: standard Preferences shortcut when applicable

### 9.2 Information architecture

Suggested tabs / sidebar sections:

1. **Wallpaper**
2. **Mode**
3. **Displays**
4. **General**
5. **Diagnostics**
6. **About**

### 9.3 Wallpaper

- Current preview (main or selected display)
- Choose image button / drop zone
- Scale mode (fill / fit / stretch / center)
- When fit: letterbox color picker
- Primary “Apply to all displays” action
- If per-display: thumbnails per screen and per-screen pickers

### 9.4 Mode

- Actual current mode (read-only badge: system wallpaper / overlay / inactive)
- Preference: auto / force system / force overlay
- Auto-fallback toggle
- Fallback notification toggle
- Backup system wallpaper before switch toggle
- “Switch now” and “Apply now” actions
- Risk copy: forcing Mode A fails in locked environments

### 9.5 Displays

- Screen list: name, main?, resolution, scale factor, bound image
- Per row: choose image, clear, use global image
- Banner after display changes: “Display configuration changed; please confirm per-display setup”

### 9.6 General

- Launch at login
- Show menu bar icon
- Open settings on launch
- (Reserved) language

### 9.7 Diagnostics

- “Run checks” button
- Result list (grouped E/A/B/R/S with status colors)
- Last check time
- Copy report / export logs (if any)
- Deep check (A03) as a separate entry, with a brief flash warning

### 9.8 About

- App name, version, build number
- Open-source license / acknowledgments (if any)
- Supported OS versions

### 9.9 Interaction constraints

- Config changes are either “apply immediately” or “explicit apply”; recommended:
  - Mode and image paths: **explicit apply** (avoid accidents)
  - Scale, colors, toggles: **immediate** or short debounce
- Destructive actions (clear per-display config, force switch) need confirmation.
- Settings itself is a normal floating window; must not use desktop-level window level.

---

## 10. Application lifecycle

### 10.1 Launch

1. Load config
2. If enabled, run health check
3. Decide target mode from `preferredMode` + check results
4. Validate image resources
5. Apply mode (A or B)
6. Register screen and workspace change observers
7. Show menu bar and settings as configured

### 10.2 While running

- Respond to screen geometry changes → rebuild / update Mode B windows, or warn that Mode A per-display config may be stale
- Respond to Apply actions from settings
- Keep modes mutually exclusive and state queryable

### 10.3 Quit

- Mode B: destroy all overlay windows
- Mode A: keep system wallpaper
- Persist current config and last mode
- Remove temporary probe leftovers (if deep check created any)

### 10.4 Launch at login

- Silent start with no UI or menu bar only (honor `openConfigOnLaunch`)
- Must not block login; init failures go into diagnostic state, not hang

---

## 11. Menu bar and notifications

### 11.1 Menu bar items (suggested)

- Current mode (read-only)
- Apply wallpaper…
- Open Settings…
- Switch to system wallpaper mode
- Switch to overlay window mode
- Run diagnostics
- Quit

### 11.2 Notification scenarios

- Mode A failed and fell back to B
- Image missing / undecodable
- Display change needs per-display confirmation
- Deep check finished

Notifications should work under system notification permission; without permission, fall back to menu bar cues or settings banners.

---

## 12. Error and fallback strategy

| Scenario | Strategy |
|----------|----------|
| Mode A locked by MDM | Mark A unavailable; in auto mode switch to B; if forced A, error |
| Image missing | Do not apply; prompt re-select; Mode B may show solid placeholder (optional; default: keep previous content or tear down overlay, no placeholder) |
| One display’s image fails, others succeed | Partial success; mark failed display in diagnostics |
| Window creation fails | Mode B fails; keep or roll back to pre-entry state |
| All screens disconnected (extreme) | Tear down windows; re-apply when screens return |
| Config corrupt | Fall back to defaults and back up the bad file |

---

## 13. Security and privacy

- Do not upload wallpapers or paths to the network (no network features this release)
- Do not scan the whole disk; only access files the user explicitly selects
- Security-scoped bookmarks: if sandboxed, persist bookmarks so images remain readable after relaunch
- Sandbox or not: engineering decision; App Store distribution requires sandbox—document bookmark flow in a later revision
- Logs must not include file contents by default—paths and error codes only

---

## 14. Performance targets (guidance)

| Item | Target |
|------|--------|
| Cold start to Mode B first paint | ≤ 1.0s (local SSD, image already selected, single display ≤ 4K) |
| Window stable after plug/unplug | ≤ 0.5s |
| Idle CPU | Near 0 (static image; no timer polling; system notifications drive work) |
| Memory | Reasonable per-display bitmap cache; no unbounded cache |

Do not poll wallpaper lock state at high frequency; checks are event-driven or user-triggered.

---

## 15. Acceptance checklist (summary)

### Features

- [ ] Mode A can set a static wallpaper (unlocked environment)
- [ ] In locked environments Mode A check fails and Mode B can be entered
- [ ] Mode B: one correct window per display
- [ ] Dock / menu bar not covered; desktop icons clickable
- [ ] Clicks through overlay region
- [ ] Mode switch leaves no leftover windows and no dual modes
- [ ] Per-display images work
- [ ] Config persists and restores after relaunch

### Display changes

- [ ] Correct window count after external display plug/unplug
- [ ] Correct frame and scale after resolution change
- [ ] After main display change, mapping is sensible or user is prompted to reconfigure

### Settings

- [ ] Each section complete; primary actions reachable
- [ ] Diagnostic report readable and copyable
- [ ] Invalid images produce clear errors

### Quit

- [ ] All Mode B windows gone after quit
- [ ] Mode A wallpaper still present

---

## 16. Logical modules (no code)

| Module | Responsibility |
|--------|----------------|
| App / Lifecycle | Launch, quit, menu bar |
| Config Store | Config read/write, defaults, migration |
| Mode Engine | Mode decision, switch transactions, mutual exclusion |
| System Wallpaper Service | Mode A read/write |
| Overlay Wallpaper Service | Mode B window management and content |
| Display Registry | Screen enumeration, stable IDs, change events |
| Image Pipeline | Pick, validate, decode, scale |
| Health Checker | Run checks and produce reports |
| Settings UI | Preferences window |
| Notifier | User-visible notifications and prompts |

Modules communicate through a clear state model; UI must not manipulate window levels directly—go through services.

---

## 17. Future extensions (placeholders only; not implemented)

- Scheduled slideshow / calendar
- Video wallpaper (still prefer native layer; watch power use)
- Auto-switch images for Dark / Light appearance
- Wallpaper history and one-click restore
- Per-Space differentiated wallpapers
- Managed-mode compliance messaging enhancements

---

## 18. Document maintenance

- This doc is the pre-implementation global constraint set; API choices, type names, and concrete APIs live in design notes or the project README.
- When changing config keys or check IDs, update this section and document config migration.
- When sandbox / distribution channel is decided, add a “Permissions and bookmarks” chapter.

---

## 19. Confirmed decisions (summary)

| Decision | Conclusion |
|----------|------------|
| Stack | Swift + AppKit |
| Modes | System wallpaper + native desktop-level overlay |
| Multi-display | Supported; one window per display |
| Dock | No geometry insets; avoid covering via desktop-level stacking |
| Content | Static images only this release |
| Settings | Required; includes mode / displays / diagnostics, etc. |
| Code in this doc | No—constraints and guidance only |
