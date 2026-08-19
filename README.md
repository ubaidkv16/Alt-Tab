<div align="center">

# AltTab

**A Windows-style Alt+Tab window switcher for macOS.**

Hold <kbd>⌥ Option</kbd> and press <kbd>Tab</kbd> to get a centred overlay of every open
**window** — not just every app — with live thumbnails, icons and titles.
Keep holding Option to cycle, release it to switch.

Native Swift · AppKit · SwiftUI · ScreenCaptureKit · no Electron

![The AltTab overlay](docs/switcher-preview.png)

</div>

---

## Features

- **Windows, not apps.** Three Chrome windows are three entries, not one.
- **Live thumbnails** captured with ScreenCaptureKit, cached and only refreshed when stale.
- **True MRU ordering.** A quick ⌥Tab tap flips between your last two windows, exactly like Windows.
- **Minimized windows** are listed, and restoring one unminimises, raises and activates it.
- **All Spaces**, multi-monitor aware — the overlay opens on the display holding the active window.
- **Menu-bar utility.** No Dock icon, no window. Idle CPU measures **0.0%**.
- **Configurable** — preview size, opacity, blur, corner radius, theme, and rebindable shortcuts.

## Requirements

macOS 14 Sonoma or newer. Apple Silicon and Intel (universal binary).

---

## Install

### From a release

1. Download **`AltTab.zip`** from the [Releases page](https://github.com/ubaidkv16/Alt-Tab/releases).
2. Double-click to extract, drag **`AltTab.app`** into **/Applications**.
3. Launch it. A setup window appears and walks you through two permissions.

macOS will say **"AltTab cannot be opened because Apple cannot check it for malicious
software."** The app is ad-hoc signed but not notarised — that needs a paid Apple
Developer account. To open it anyway, do either:

- **Right-click** `AltTab.app` → **Open** → **Open**, or
- **System Settings → Privacy & Security**, scroll down, **Open Anyway**.

Once only.

### From source

```sh
git clone https://github.com/ubaidkv16/Alt-Tab.git
cd Alt-Tab
./build.sh
```

Produces `dist/AltTab.app` (universal, Release, ad-hoc signed), plus `AltTab.zip`
and `AltTab.dmg`. Needs Xcode 16+.

---

## Permissions

AltTab's setup window stays open until both are sorted, and the menu-bar icon is
**slashed** whenever AltTab is not actually listening — so this never fails silently.

| Permission | Needed for | Required? |
|---|---|---|
| **Accessibility** | Enumerating windows, reading titles, raising and unminimising them, and receiving ⌥Tab globally | **Yes** |
| **Screen Recording** | Window thumbnails | Optional — without it you get application icons |

1. **Accessibility** — click *Open Accessibility Settings* in the setup window, then switch
   **AltTab** on under *Privacy & Security → Accessibility*. It starts listening within a
   second; no relaunch needed.
2. **Screen Recording** — AltTab asks for this itself once it can. Switch **AltTab** on under
   *Privacy & Security → Screen Recording*, then click **Relaunch to Enable Previews**.
   macOS only hands a process this grant at start-up, so previews stay dark until it restarts.

> [!IMPORTANT]
> **Rebuilding or updating the app resets its permissions.** Ad-hoc signatures are a hash of
> the binary, so a new build is a new identity to macOS. After replacing `AltTab.app`, re-toggle
> it in both lists — and delete any stale duplicate row with the **−** button. This is the
> price of not having a Developer ID; a notarised build would not have this problem.

---

## Keyboard

| Keys | Action |
|---|---|
| <kbd>⌥</kbd><kbd>Tab</kbd> | Open the switcher / select the next window |
| <kbd>⌥</kbd><kbd>⇧</kbd><kbd>Tab</kbd> | Select the previous window |
| <kbd>⌥</kbd> held + <kbd>Tab</kbd> | Keep cycling |
| Release <kbd>⌥</kbd> | Activate the selected window |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Navigate the grid |
| <kbd>Return</kbd> | Activate the selected window |
| <kbd>Esc</kbd> | Close without switching |

Mouse works too — hover to select, click to activate.

All three shortcuts are rebindable in **Settings → Keyboard**. The switcher stays open for as
long as the modifier of the *Next window* shortcut is held.

### Ordering

Windows are ordered most-recently-used, never alphabetically. Index 0 is the window you are in
now; index 1 is the one you were in before — which is why a quick tap flips between the last two.

```
Chrome → VS Code → Terminal → Chrome     ⇒  the next ⌥Tab selects Terminal
```

## Settings

Menu-bar icon → **Settings…**

- **General** — Enable Alt+Tab · Launch at Login · Show menu-bar icon · live permission status
- **Behavior** — Include minimized windows · Include windows from all Spaces · Show window titles · Show application icons
- **Appearance** — Preview size · Theme (System/Light/Dark) · Background blur · Background opacity · Corner radius
- **Keyboard** — Next / Previous / Cancel shortcut recorders

---

## Troubleshooting

**⌥Tab does nothing.** Open the menu-bar menu — the first line tells you why. A slashed icon
means AltTab is not listening. Usually Accessibility is off, or was reset by an update.

**Previews show app icons instead of thumbnails.** Screen Recording is off, or was granted while
AltTab was already running. Grant it, then **Relaunch to Enable Previews**.

**It worked, then stopped after I updated the app.** Permissions were reset by the new binary's
hash. Re-toggle both, and remove stale duplicate rows.

**Two AltTab entries in System Settings.** You have run two copies (e.g. `dist/` and
`/Applications/`). Quit both, delete the stale row with **−**, keep only `/Applications/AltTab.app`.

**⌥Tab dead in one specific app.** That app has *secure input* enabled (password fields, some
password managers). macOS blocks all event taps while it is active. No switcher can work around it.

**Nothing above helps.** Run the built-in self-test:

```sh
/Applications/AltTab.app/Contents/MacOS/AltTab --self-test ~/Desktop
```

It checks grid geometry, MRU ordering and shortcut handling, renders the overlay offscreen to
`~/Desktop/switcher-preview.png`, then reports live permission status, enumerates your real
windows and captures a real thumbnail. For a running trace:

```sh
ALTTAB_DEBUG=1 /Applications/AltTab.app/Contents/MacOS/AltTab
```

---

## Development

Open **`Package.swift`** in Xcode — it is treated as a first-class project with an `AltTab`
scheme. Command line works too:

```sh
swift build -c release                                    # binary only
xcodebuild -scheme AltTab -configuration Release build     # via Xcode
./build.sh                                                 # .app + .zip + .dmg
```

There is deliberately no `.xcodeproj`: it would be a second source of truth for the same target,
and `swift package generate-xcodeproj` has been deprecated by Apple since Xcode 13.

### Layout

```
Sources/AltTab/
├── App/                 main, AppDelegate, menu-bar item, self-test
├── WindowManagement/    window model, AX enumeration, MRU, focus tracking, activation
├── Preview/             ScreenCaptureKit thumbnail cache
├── Input/               CGEventTap global keyboard monitor
├── Permissions/         permission detection + setup UI
├── UI/                  floating panel, SwiftUI overlay, grid geometry
├── Settings/            preferences model, settings window, shortcut recorder
└── Utilities/           AXUIElement helpers, debug logging
```

### APIs

| Need | API |
|---|---|
| Window enumeration | Accessibility — `AXUIElementCopyAttributeValue`, `kAXWindowsAttribute` |
| Window previews | **ScreenCaptureKit** — `SCShareableContent`, `SCScreenshotManager.captureImage` |
| Window activation | Accessibility — `kAXRaiseAction`, `kAXMinimizedAttribute`, `kAXFrontmostAttribute` |
| Global keyboard | `CGEvent.tapCreate` on a dedicated thread |
| Focus / MRU tracking | `AXObserver` + `NSWorkspace` notifications — event-driven, no polling |
| Displays | `NSScreen` |
| Launch at login | `SMAppService` |

Accessibility is used for enumeration rather than `CGWindowListCopyWindowInfo` because it is the
only API that reports minimized windows and windows on other Spaces *and* can act on them.
`CGWindowList` is used once at launch, purely to seed an initial z-order for the MRU list.

The event tap runs on its own thread so a busy main thread can never make macOS disable it, and
the overlay is a `.nonactivatingPanel` so showing it never steals focus from the app you are in.

### Performance

- Nothing is captured or polled while the switcher is closed — **0.0% idle CPU**, ~70 MB resident,
  flat across 50+ open/close cycles.
- The window list is kept warm by focus/launch/quit notifications, so the overlay paints from
  cache on the first frame and reconciles asynchronously.
- Thumbnails are cached per window id, re-captured only when older than 4s, capped at 80 entries
  and pruned when windows disappear.

### Cutting a release

`dist/` is gitignored, so binaries live in GitHub Releases:

```sh
./build.sh
gh release create v1.0 dist/AltTab.zip dist/AltTab.dmg \
  --title "AltTab 1.0" --notes "First release."
```

---

## Known macOS limitations

- **Secure input.** While a password field has secure input enabled, macOS blocks all event taps
  and ⌥Tab will not fire. Affects every third-party switcher; there is no supported workaround.
- **Screen Recording is required for thumbnails.** There is no API to read window contents without
  it. Denied, AltTab shows application icons — deliberately, not as an error.
- **Minimized windows cannot be captured.** A minimized window has no surface in the window server,
  so its tile shows the last cached thumbnail if there is one, otherwise the app icon, with a badge.
- **`_AXUIElementGetWindow`.** Mapping an accessibility window to its window-server id has no public
  API. AltTab uses this long-standing private symbol, as every macOS window switcher does. Fine for
  personal use; the Mac App Store would reject it.
- **Full-screen Spaces.** Activating a window in its own full-screen Space triggers the standard
  macOS Space-switch animation. That delay is the system's, not AltTab's.
- **Not notarised.** See the Gatekeeper and permission-reset notes above.

## Contributing

Issues and pull requests welcome. Please run the self-test before opening a PR:

```sh
swift build -c release && .build/release/AltTab --self-test /tmp
```

## License

MIT — see [LICENSE](LICENSE).

## Credits

Inspired by the Windows 10/11 Alt+Tab switcher, and by
[alt-tab-macos](https://github.com/lwouis/alt-tab-macos), which pioneered this approach on macOS.
