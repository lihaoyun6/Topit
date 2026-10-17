import AppKit

@main
struct RegionPanelFocusTests {
    static func main() {
        _ = NSApplication.shared
        let panel = RegionPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL \(label)") }
        }
        // Never show/order this test panel or request system keyboard focus.
        check(!panel.canBecomeKey, "ordinary source interaction cannot give the crop keyboard focus")
        panel.allowsKeyboardFocus = true
        check(panel.canBecomeKey, "region selection and Shift editing can use panel keyboard focus")
        panel.allowsInteraction = false
        check(!panel.canBecomeKey, "auto-hide blocks focus even when Shift was held")
        panel.allowsInteraction = true
        panel.allowsKeyboardFocus = false
        check(!panel.canBecomeKey, "leaving Shift editing returns keyboard ownership to the source")
        if failures > 0 { exit(1) }
        print("Passed \(checks) panel focus-ownership checks")
    }
}
