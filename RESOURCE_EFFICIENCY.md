# Capture resource policy

Pinned-window capture now defaults to 30 Hz, a 3-frame `SCStream` queue, and a
2560-pixel long-edge cap. The cap preserves aspect ratio and is intentionally
conservative for very large windows while retaining enough backing pixels for
legible text. `Balanced` raises the cap to 3840 pixels and `Native` disables
the cap. Existing `maxFps` values migrate by decoding the stored value; the
old `65535` sentinel remains **No Limit**, while a missing or unknown value is
30 Hz.

Adaptive mode begins at 10 Hz and is promoted during the existing resize/motion
path. Explicit 60 Hz, 120 Hz, and No Limit selections are never downgraded.
The manager owns the stream lifecycle and coalesces configuration updates by
ignoring duplicate starts/stops, so resize transitions do not create parallel
streams. The current low-rate window-frame observer remains as a reliable
fallback because ScreenCaptureKit does not expose a universal per-window frame
change notification on every supported system.

Debug diagnostics are available on `ScreenCaptureManager.diagnostics`: active
pin count, configured dimensions, configured FPS, queue depth, and calculated
raw BGRA frame bytes. Release builds do not continuously log frame details.

The deployment target is macOS 26.0, matching the installed macOS 26.5 SDK.
The project retains its universal arm64+x86_64 setting; Intel compatibility is
claimed only after a Release archive is inspected for both architectures.
