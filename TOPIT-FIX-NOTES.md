# Topit memory + stability fixes (this branch)

Upstream OSS repo (lihaoyun6/Topit); this branch keeps changes minimal,
revertible, upstream-acceptable. Larger redesign ideas are in
`V2-REWRITE-NOTES.md`, not in code.

## What was wrong (with evidence)

1. **Selector leaked one SCStream per window per open** (`SCManager.swift`
   `setupStreams`): `streams.removeAll()` dropped running streams without
   stopping them; each loop iteration stopped only the just-created preview
   stream. Every overview open/refresh orphaned N IOSurface queues → idle
   memory grew monotonically past 650 MB, never released.
2. **Thumbnail decode on main thread** (`SCManager.swift` stream delegate):
   fresh `CIContext` + CIImage→CGImage→NSImage per frame on
   `sampleHandlerQueue: .main` → 13–33% CPU spikes on focus/move.
3. **Force-unwrap crash in grid** (`ContentView.swift:128,142`):
   `item.window.owningApplication!`, `getAppIcon(...)!`, `title!` trap on
   untitled/iconless windows.
4. **Pin panel reuse orphaned timers/streams** (`Accessibility.swift`
   `createNewWindow`): replacing `contentView` never fires `windowWillClose`,
   so the old OverlayView's 200 ms timer + capture manager kept polling →
   CPU spikes, use-after-teardown risk.
5. **Stop/restart race killed pins** (`SCManager.swift` `stopCapture`):
   `stopping=true` until async completion; start/resume early-returned while
   set. The move/resize tick stops then promptly restarts → restart dropped →
   black/frozen pin; move killed pinning.
6. **Move path tore down the pin** (`OverlayView.swift` tick): stop + later
   restart instead of live `updateConfiguration` reconfig.
7. **Opacity close+recreate lost the window** (`OverlayView.swift:173`,
   `OverlayViewOpacity.swift:160`): `nsWindow.close()` + refetch via mouse
   screen + `createNewWindow` races teardown; refetch can return nil → no
   window at all.
8. **Highlight masks never deallocated** (`WindowHighlighter.swift`):
   `isReleasedWhenClosed=false` + stale `mask` reference after close →
   panels + hosting views accumulated per selection session.
9. **Sample buffers hopped to main before enqueue** (`SCManager.swift:86`):
   retained IOSurface past handler lifetime; valid frames dropped across
   restarts.
10. **Sync content fetch on main** (`updateAvailableContentSync`): semaphore
    block on main-thread paths (launch, pin/unpin, opacity) → UI freeze,
    ANR risk. (Noted, not changed — callers still use it; v2 should go async.)

## Fixes applied (this branch)

- Preview streams: stop (remove output + `stopCapture`) before drop; shared
  `thumbContext`; sample queue `.global(qos: .userInitiated)`; decode stays
  off main.
- Pin capture output enqueued on the sample-handler queue, identity-checked
  without main hop.
- Start/resume: wait ≤1 s for in-flight stop instead of dropping (fixes
  black pins); move path reconfigures live, never stops; close-on-missing
  only when actually capturing.
- Grid: safe icon/title fallbacks, no force-unwraps.
- `createNewWindow`: closes stale panel (fires `windowWillClose`, invalidates
  timer, stops capture) instead of swapping contentView.
- Opacity sliders: in-place `nsWindow.alphaValue`, no close/recreate.
- Masks/covers: `isReleasedWhenClosed=true`, `mask=nil` on close.

## Verification

- `xcodebuild ... CODE_SIGNING_ALLOWED=NO ... build` → **BUILD SUCCEEDED**
  (unsigned typecheck; Debug signing cert absent on this machine).
- Runtime verification still needed on your Mac (I have no GUI session):
  pin/unpin, pin-via-overview, stoplight options, overview open/close vs
  `ps`/Activity Monitor (target <300 MB, drops after unpin), move/resize
  no-crash, transparency stays controllable, artifacts minimal.
- `stopPreviewStream` is now `throws` + removes output; old-stream teardown
  awaits it (`try? await`), so refresh is serial and bounded.

## V2 (own rewrite, not upstream)

See `V2-REWRITE-NOTES.md`.
