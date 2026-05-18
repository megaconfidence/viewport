# Viewport

A native macOS menu bar app for resizing the active window to common landscape and vertical sizes.

The original AppleScript version depended on each app exposing scriptable window bounds. This rewrite uses the macOS Accessibility API first, then falls back to AppleScript bounds for scriptable apps such as Chrome and Firefox when Accessibility reports success but does not actually resize the window.

## Features

- Native macOS menu bar app
- Configurable list of predefined landscape and vertical presets
- Centers the resized window on its current display
- Respects the visible screen area, including the menu bar and Dock
- Scales a preset down when the current display is too small
- Uses Accessibility APIs with an AppleScript fallback for scriptable apps

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools or Xcode with Swift support
- Accessibility permission for the built app
- Automation permission for apps that need the AppleScript fallback

## Build

```sh
scripts/build-app.sh
```

The app bundle is created at:

```text
.build/Viewport.app
```

Move that app into `/Applications` if you want it to behave like a normal installed app.

## Usage

1. Launch `Viewport.app`.
2. Grant Accessibility permission when prompted.
3. Click the menu bar icon.
4. Choose a target size.

Press `Control` + `Option` + `Command` + `V` from any app to resize the active window to the last-used preset. Fresh installs default to `1920 × 1080`; choosing another size makes that the new shortcut target.

To choose which sizes appear in the menu, or to change the shortcut, select `Settings…`. The selected presets and shortcut are stored in user defaults.

For Chrome, Firefox, or other apps that need the fallback, macOS may also ask whether Viewport can control that app. Allow it so the app can use the browser's native AppleScript `bounds` support.

If permission is not granted, open:

```text
System Settings > Privacy & Security > Accessibility
```

Then enable `Viewport` and choose a size again.

## How It Works

The app reads the focused window through `AXUIElementCreateSystemWide`, then sets its `kAXSizeAttribute` and `kAXPositionAttribute`. If the menu bar interaction causes focus to move away from the target app, it falls back to the last frontmost application observed by `NSWorkspace`.

Before Accessibility resizing, the app temporarily disables `AXEnhancedUserInterface` for the target app when present, then applies a `size -> position -> size` sequence. It reads the frame back afterward; if the resize did not apply, it tries AppleScript `bounds` against the target app.

## Known Limitations

- Full-screen Spaces windows generally cannot be resized this way.
- Minimized windows are not targeted.
- Some apps intentionally restrict Accessibility-driven window changes.
- Nonstandard windows, games, and protected system UI may refuse resize or move requests.
