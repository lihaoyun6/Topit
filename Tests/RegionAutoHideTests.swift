import Foundation
import CoreGraphics

@main
struct RegionAutoHideTests {
    static func main() {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL \(label)") }
        }
        var gesture = RegionAutoHideGesture()
        func flags(_ control: Bool, _ time: TimeInterval, other: Bool = false) -> Bool {
            gesture.modifiersChanged(control: control, otherModifiers: other, timestamp: time)
        }
        func tap(_ time: TimeInterval) -> Bool {
            _ = flags(true, time)
            return flags(false, time + 0.05)
        }
        check(!tap(1), "a single tap does not toggle")
        check(!flags(true, 1.2), "the second press does not toggle before release")
        check(flags(false, 1.25), "two isolated taps toggle on release")
        check(!tap(1.4), "a third tap does not toggle again")
        check(tap(1.6), "a fourth tap completes another pair")
        gesture.reset()
        check(!tap(2) && !tap(2.6), "slow taps do not toggle")
        gesture.reset()
        _ = tap(3)
        _ = flags(true, 3.2)
        check(!flags(false, 3.6), "a long second hold cancels the pair")
        check(!tap(3.7), "a long hold cannot seed the next pair")
        gesture.reset()
        _ = tap(4)
        _ = flags(true, 4.2)
        gesture.cancel() // keyDown: Control+C, Control+Space, etc.
        check(!flags(false, 4.25), "Control chords do not toggle")
        check(!tap(4.4), "a chord cannot seed the next pair")
        gesture.reset()
        _ = tap(5)
        _ = flags(true, 5.2, other: true)
        _ = flags(true, 5.22)
        check(!flags(false, 5.25), "other modifiers held during a tap cancel it")
        gesture.reset()
        _ = tap(6)
        _ = flags(false, 6.1, other: true)
        _ = flags(false, 6.15)
        check(!tap(6.2), "a modifier between taps cancels the pair")
        gesture.reset()
        _ = tap(7)
        gesture.cancel() // any mouse-down or scroll event
        check(!tap(7.2), "pointer interaction between taps cancels the pair")
        gesture.reset()
        _ = flags(true, 8)
        _ = flags(true, 8.01) // overlapping left and right Control
        check(!flags(false, 8.05) && !tap(8.2), "overlapping Control keys cannot form a pair")
        gesture.reset()
        _ = tap(9)
        _ = flags(true, 8)
        check(!flags(false, 8.05), "timestamp reset clears a stale tap")
        gesture.reset()
        _ = tap(10)
        gesture.reset()
        check(!tap(10.2), "mode changes reset a half-finished gesture")

        let frame = CGRect(x: -600, y: 200, width: 240, height: 160)
        func hides(_ x: CGFloat, _ y: CGFloat, hidden: Bool = false) -> Bool {
            RegionAutoHideVisibility.shouldHide(pointer: CGPoint(x: x, y: y), frame: frame, currentlyHidden: hidden)
        }
        check(hides(-480, 280), "pointer inside the region hides it")
        check(hides(-615, 280), "pointer approaching within 18pt hides it")
        check(!hides(-625, 280), "visible panel stays visible outside the approach margin")
        check(hides(-625, 280, hidden: true), "hidden panel keeps a 30pt exit margin")
        check(!hides(-635, 280, hidden: true), "leaving the exit margin restores visibility")
        check(hides(-480, 375), "approach above a panel works in AppKit coordinates")
        check(!hides(500, 280, hidden: true), "pointer on another screen restores visibility")
        if failures > 0 { exit(1) }
        print("Passed \(checks) auto-hide gesture and proximity checks")
    }
}
