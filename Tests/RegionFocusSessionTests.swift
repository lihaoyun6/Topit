import Foundation

@main
struct RegionFocusSessionTests {
    static func main() {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL \(label)") }
        }
        let firstApp = RegionFocusTarget(windowID: 1, processID: 1)
        let grok = RegionFocusTarget(windowID: 2, processID: 2)
        let codex = RegionFocusTarget(windowID: 3, processID: 3)
        let secondCodex = RegionFocusTarget(windowID: 4, processID: 3)
        var session = RegionFocusSession()
        _ = session.begin(grok, current: firstApp, focus: { _ in true })
        _ = session.begin(codex, current: grok, focus: { _ in true })
        check(session.previous == firstApp, "switching source crops retains uninterrupted restoration")
        check(session.end(grok, current: codex) == nil && session.active == codex, "closing old Grok crop cannot end new Codex focus")
        check(session.end(codex, current: codex) == firstApp && session.active == nil, "ending the active crop clears the session")
        _ = session.begin(grok, current: firstApp, focus: { _ in true })
        _ = session.begin(grok, current: codex, focus: { _ in true })
        check(session.previous == codex, "a manual foreground switch replaces stale restoration")
        _ = session.end(grok, current: grok)
        _ = session.begin(codex, current: secondCodex, focus: { _ in true })
        check(session.previous == secondCodex, "another window of the same app is a valid restoration target")
        check(session.end(codex, current: secondCodex) == nil, "closing a crop cannot steal focus from another window of its app")
        check(session.active == nil && session.previous == nil, "end clears all state even when restoration is skipped")
        _ = session.begin(grok, current: firstApp, focus: { _ in true })
        check(session.end(grok, current: codex) == nil, "source closure after switching apps cannot restore an old app")
        check(session.active == nil && session.previous == nil, "closed sources leave no session state")
        check(!session.begin(codex, current: firstApp, focus: { _ in false }) && session.active == nil, "failed focus cannot start a session")
        _ = session.begin(codex, current: codex, focus: { _ in true })
        check(session.previous == nil, "already-focused source does not restore to itself")
        _ = session.end(codex, current: codex)
        _ = session.begin(codex, current: firstApp, focus: { _ in true })
        _ = session.begin(codex, current: codex, focus: { _ in true })
        check(session.previous == firstApp, "repeated clicks preserve the original restoration target")
        check(session.end(codex, current: secondCodex) == nil, "manual same-app window switch prevents restoring an unrelated app")
        _ = session.begin(grok, current: firstApp, focus: { _ in true })
        check(session.end(grok, current: nil) == nil && session.active == nil && session.previous == nil,
              "a closed foreground process clears the session without stealing focus")
        if failures > 0 { exit(1) }
        print("Passed \(checks) focus-session lifecycle checks")
    }
}
