# ScreenMarker

A tiny macOS menu-bar app for drawing on your screen — handy for annotating while you share your screen in Microsoft Teams, Zoom, or during a PowerPoint slide show.

Single Swift file, no Xcode project, no dependencies.

## Features

- Freehand pen that draws over everything, on every display
- 7 colours (red, orange, yellow, green, blue, white, black) and 3 pen sizes
- Undo and Erase All
- Lives in the menu bar — nothing floating on your desktop
- Global shortcuts that work in any app, including full-screen slide shows
- No Accessibility or Screen Recording permissions required

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌃⌥D | Toggle the pen on/off |
| Esc | Stop drawing (returns control to the app underneath) |
| ⌃⌥Z | Undo last stroke (on the screen under the pointer) |
| ⌃⌥X | Erase all drawings |
| ⌃⌥M | Open the ScreenMarker menu at the pointer |
| Right-click | Open the menu while drawing |

When the menu bar is hidden (e.g. a PowerPoint slide show), use ⌃⌥M or right-click to change colour or size.

## Build & install

Requires macOS 12+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
cp -R build/ScreenMarker.app /Applications/
open /Applications/ScreenMarker.app
```

The app is ad-hoc signed. If macOS blocks it on first launch, right-click the app in Finder and choose **Open**.

## Using it in a Teams call

Share your **entire screen**, not a single window. Teams only captures the chosen window's pixels when sharing a window, so the drawing layer won't be included. PowerPoint Live and the Teams whiteboard aren't screen shares either, so drawings won't appear there.

With multiple displays, only drawings on the display you're sharing are visible to attendees.

## Tips

- Can't see the menu-bar icon on a display? macOS hides status icons when the menu bar runs out of room. ⌘-drag the ✎ icon closer to the clock so it's dropped last.
- Picking a colour from the menu also turns the pen on.
- The menu-bar icon fills in and takes on the pen colour while drawing.
