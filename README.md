# 
<p align="center">
<img src="./Topit/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">Topit</h1>
<h3 align="center">Pin any window to the top of your screen<br><br>
<a href="./README_zh.md"><img src="https://img.shields.io/badge/中文-README-green" height="24" alt="中文版本"/></a>
<a href="https://lihaoyun6.github.io/topit/"><img src="https://img.shields.io/badge/Leading%20Page-blue" height="24" alt="Leading Page"/></a></h3> 
</p>

> Public feature fork: [UnityX103/Topit](https://github.com/UnityX103/Topit), based on [lihaoyun6/Topit](https://github.com/lihaoyun6/Topit). Region-pinning modifications maintained since 2026-10-17, under the original AGPL-3.0 license. [Releases](https://github.com/UnityX103/Topit/releases) · [CI](https://github.com/UnityX103/Topit/actions/workflows/ci.yml) · [Release process](docs/RELEASING.md).

## Screenshots
<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/preview_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/preview.png">
  <img alt="xHistory Screenshots" src="./img/preview.png" width="816"/>
</picture>
</p>

## Installation and Usage
### System Requirements:
- macOS 13.0 and Later  

### Installation:
Download this fork from [GitHub Releases](https://github.com/UnityX103/Topit/releases). The upstream Homebrew formula installs the upstream app and does not include these modifications. Current fork releases use a fixed local signing certificate and are not Apple Developer ID notarized.

### Usage: 
- Topit can pin windows from any application to the top of your workspace.  

- Just open Topit and select the window you want to pin, and it will do the rest.  
- Topit can pin any number of windows. You can move, resize or interact with them at any time.  

## Q&A
**1. Why does Topit need screen recording and accessibility permissions?**
> Topit uses the accessibility permissions and screen recording permissions to control and capture your windows.  

**2. Does Topit consume a lot of power?**
> Topit uses ScreenCapture Kit to capture windows with a lower CPU overhead. But it may still drain the battery faster when you pin too many windows. 

## Donate
<img src="./img/donate.png" width="350"/>

## Thanks
[Sparkle](https://github.com/sparkle-project/Sparkle) @Sparkle  
[ChatGPT](https://chat.openai.com) @OpenAI  

## Local region-pinning build

Choose **Pin a Region…** in the window selector or menu bar, or press **Command–Shift–T** (configurable in Settings). The shortcut immediately opens cropping on the window under the pointer. From the selector, click a source window, then drag a rectangle and release. Esc cancels; selections smaller than 8 points are ignored.

Only the selected region appears in an independent live floating panel. The live panel forwards clicks, drags, scrolling, and keyboard input to its source. Hold Shift to edit the panel: drag to move, resize proportionally from an edge, or hover for Close, Freeze, and Copy Snapshot. Shift-right-click opens opacity and panel options. Release Shift to resume source interaction. Frozen panels do not forward input. Freeze stops the stream and keeps a still screenshot; Resume restarts it. Live regions are capped at 30 fps. Unpin All closes region panels too. Closing a source retains its last frame.

The original window keeps its normal stacking order. Window capture works through occlusion; minimized windows, Spaces and protected content depend on macOS and the source application. Updates use the same fixed local signing certificate; the initial migration from ad-hoc signing may require one final permission grant. The upstream updater is disabled in this feature build so official releases cannot overwrite the local changes automatically.

Run `Tests/run-region-tests.sh` for geometry and synthetic-frame regression checks. Build the `Topit` scheme in Xcode.

Background left-button gestures use macOS Command-click semantics to preserve window ordering. Some controls, including links, may interpret them as Command-clicks. Pointer routing dynamically resolves CGEventSetWindowLocation; it refuses to send a click if this system interface is unavailable. Background input remains application-dependent and requires installed-app acceptance.

Double-tap Control to toggle auto-hide for all region panels, or use the Region Capture/menu bar menu. In this mode panels fade out as the pointer approaches and reappear after it leaves; mouse, keyboard and Shift editing stay disabled until the mode is switched off. Control chords, long holds, and clicks or scrolling between taps cancel the gesture. New panels inherit the current mode; restarting defaults to interaction mode.

Region clicks transfer real keyboard/IME focus to the original window/control. Topit creates no local editor, copies no draft values, and synthesizes no keyboard events. Return, paste, undo and input methods are handled by the source application. The no-raise focus request uses dynamically resolved macOS private window-focus interfaces; unavailable interfaces produce a visible error. App-specific compatibility and ordering require installed-version acceptance.
