import AppKit
import Darwin

@main
struct RegionEventFactoryTests {
    static func main() {
        var failed = 0
        func check(_ condition: Bool, _ label: String) {
            if !condition { failed += 1; print("FAIL \(label)") }
        }
        let sourceWindow: CGWindowID = 34567
        let floatingWindow = 98765
        let pointer = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: floatingWindow, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        let frame = CGRect(x: 400, y: 100, width: 600, height: 400)
        let point = CGPoint(x: 530, y: 240)
        typealias WindowLocation = @convention(c) (CGEvent) -> CGPoint
        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventGetWindowLocation")!
        let getWindowLocation = unsafeBitCast(symbol, to: WindowLocation.self)
        var mouseChecks = 0
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            let original = NSEvent.mouseEvent(with: type, location: CGPoint(x: 12, y: 30),
                modifierFlags: .option, timestamp: 12, windowNumber: floatingWindow,
                context: nil, eventNumber: 4, clickCount: 1, pressure: 0.5)!
            for background in [false, true] {
                let routed = RegionEventFactory.mouse(original, windowID: sourceWindow, processID: 12345,
                    point: point, sourceFrame: frame, keepInBackground: background)!
                check(!routed.flags.contains(.maskCommand), "ordinary background click must not become Command-click")
                check(routed.flags.contains(.maskAlternate), "user Option modifier preserved")
                check(NSEvent(cgEvent: routed)?.windowNumber == Int(sourceWindow), "mouse targets source window")
                check(routed.location == point, "source screen point preserved")
                check(routed.getIntegerValueField(.eventTargetUnixProcessID) == 12345, "mouse targets source process")
                check(routed.getIntegerValueField(.mouseEventWindowUnderMousePointer) == Int64(sourceWindow), "source hit window preserved")
                check(!background || routed.getIntegerValueField(.mouseEventSubtype) == 3, "background gesture tagged for per-process dispatch")
                let windowPoint = getWindowLocation(routed)
                let expectedPoint = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                check(windowPoint == expectedPoint, "window-local point survives setting global screen coordinates (got \(windowPoint), expected \(expectedPoint))")
                mouseChecks += 8
            }
        }
        check(RegionEventFactory.mouse(pointer, windowID: 0, processID: 12345,
            point: point, sourceFrame: frame, keepInBackground: true) == nil, "zero window ID rejected")
        mouseChecks += 1
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 20, wheel2: 0, wheel3: 0)!
        scroll.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(floatingWindow))
        check(RegionEventFactory.targetPointer(scroll, windowID: sourceWindow, processID: 12345,
            point: point, sourceFrame: frame), "scroll retargeting supported")
        check(NSEvent(cgEvent: scroll)?.windowNumber == Int(sourceWindow), "scroll replaces floating-window number")
        check(getWindowLocation(scroll) == CGPoint(x: 130, y: 140), "scroll has source-local location")
        check(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 20, "scroll distance preserved")
        mouseChecks += 4
        let commandClick = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: .command, timestamp: 12, windowNumber: floatingWindow,
            context: nil, eventNumber: 5, clickCount: 1, pressure: 1)!
        let routedCommand = RegionEventFactory.mouse(commandClick, windowID: sourceWindow,
            processID: 12345, point: point, sourceFrame: frame, keepInBackground: true)!
        check(routedCommand.flags.contains(.maskCommand), "a real user Command-click retains Command")
        mouseChecks += 1
        let nonTextPointer = RegionEventFactory.mouse(pointer, windowID: sourceWindow, processID: 12345,
            point: point, sourceFrame: frame, keepInBackground: true, preventWindowOrdering: true)!
        check(nonTextPointer.flags.contains(.maskCommand), "non-text pointer can explicitly preserve source ordering")
        mouseChecks += 1;
        if failed > 0 { print("\(failed) event-routing checks failed"); exit(1) }
        print("Passed \(mouseChecks) pointer-routing checks")
    }
}
