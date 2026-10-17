import AppKit

@main
struct SelectionEventTests {
    static func main() {
        var failures = 0
        var checks = 0
        func check(_ event: NSEvent, expected: Bool, label: String) {
            var result = false
            let exception = TopitCatchException { result = SelectionEventPolicy.cancelsSelection(event) }
            checks += 1
            if let exception {
                print("FAIL \(label): \(exception.reason ?? exception.name.rawValue)")
                failures += 1
            } else if result != expected {
                print("FAIL \(label): unexpected cancellation")
                failures += 1
            }
        }
        func key(_ type: NSEvent.EventType, _ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: code)!
        }
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown] {
            let event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            check(event, expected: false, label: "\(type): no keyboard access for pointer events")
        }
        check(key(.keyDown, 53), expected: true, label: "Escape down cancels")
        check(key(.keyUp, 53), expected: false, label: "Escape up does not cancel twice")
        check(key(.keyDown, 17), expected: false, label: "ordinary keys do not cancel")
        check(key(.flagsChanged, 56), expected: false, label: "Shift does not cancel")
        print("\(checks - failures)/\(checks) selection-event checks passed")
        if failures > 0 { exit(1) }
    }
}
