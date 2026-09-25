# Topit v2 rewrite notes (own version, NOT for upstream)

Collected during the memory/stability fix pass. These do not belong in the
upstream PR; they are direction for our own build.

1. **No-overview default mode.** The selector's per-window SCStream grid is
   the bulk of the cost. V2: pin-by-click / pin-frontmost / shortcuts first;
   overview opt-in, thumbnails via `CGWindowListCreateImage` stills (not live
   streams), bounded LRU cache, aggressive downscale (<160px), no reload on
   focus/move.
2. **Single capture engine.** One stream per pin, generation-counted
   stop/restart, live `updateConfiguration` on move/resize, serial teardown.
   Never parallel streams for one window.
3. **Async content everywhere.** Remove `updateAvailableContentSync`
   semaphore path; `SCShareableContent` fetch async with cancellation and
   stale-result discard.
4. **In-place translucency.** `alphaValue`/material changes only; no window
   recreation, no display-from-mouse, no refetch race.
5. **Panel lifecycle ownership.** One owner for pin panels; close always fires
   teardown (timer invalidate, stream stop, layer flush); no contentView swaps.
6. **Background decode, shared contexts.** One CIContext/Metal context;
   thumbnails decoded off main; preview queue depth 1–2, not 3.
7. **Memory budget + telemetry.** Per-pin byte accounting (frame bytes =
   w×h×4 × queue), 300 MB budget with LRU eviction, debug overlay showing
   pins/dimensions/fps/queue — already stubbed via `CaptureDiagnostics`.
8. **Firefox-style pin study.** The referenced Firefox-based pin-on-top does
   it without artifacts/bloat — likely OS-compositor pinning or single
   still + move-tracking rather than continuous capture. Spike: compare
   `CGWindowListCreateImage` + AX move observer vs SCStream for static
   windows; use SCStream only for animating content.
9. **New kits to evaluate:** ScreenCaptureKit `SCScreenshotManager` stills
   (macOS 14+), `CGWindowListCreateImage` thumbnails, AX `kAXWindowMoved`
   notifications instead of 200 ms polling, `IOSurface` pool reuse.
10. **Test harness:** scripted pin/unpin cycles with `footprint` sampling,
    move/resize fuzz, transparency sweep, overview open/close × 20 with
    before/after RSS assert (<300 MB, drops after release).
