import AppKit
import Darwin

/// Build events for one source window; event construction never activates an application.
enum RegionEventFactory {
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private static let setWindowLocation: SetWindowLocation? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(symbol, to: SetWindowLocation.self)
    }()

    /// NSEvent cannot look up another process's NSWindow to fill this coordinate.
    /// Set screen and window positions independently; refuse to guess if unavailable.
    @discardableResult
    static func targetPointer(_ event: CGEvent, windowID: CGWindowID, processID: pid_t,
                              point: CGPoint, sourceFrame: CGRect) -> Bool {
        guard windowID != 0, processID > 0, let setWindowLocation else { return false }
        event.location = point
        setWindowLocation(event, CGPoint(x: point.x - sourceFrame.minX, y: point.y - sourceFrame.minY))
        // Native window-number field is also needed when retargeting scroll events.
        event.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(processID))
        return true
    }

    static func mouse(_ event: NSEvent, windowID: CGWindowID, processID: pid_t,
                      point: CGPoint, sourceFrame: CGRect, keepInBackground: Bool,
                      preventWindowOrdering: Bool = false) -> CGEvent? {
        let types: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                           .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                           .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved]
        guard types.contains(event.type), windowID != 0, processID > 0 else { return nil }
        let local = CGPoint(x: point.x - sourceFrame.minX, y: sourceFrame.maxY - point.y)
        guard let routed = NSEvent.mouseEvent(with: event.type, location: local,
            modifierFlags: preventWindowOrdering ? event.modifierFlags.union(.command) : event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: Int(windowID), context: nil, eventNumber: event.eventNumber,
            clickCount: event.clickCount, pressure: event.pressure)?.cgEvent else { return nil }
        routed.setIntegerValueField(.mouseEventButtonNumber, value: Int64(event.buttonNumber))
        guard targetPointer(routed, windowID: windowID, processID: processID,
                            point: point, sourceFrame: sourceFrame) else { return nil }
        if keepInBackground { routed.setIntegerValueField(.mouseEventSubtype, value: 3) }
        return routed
    }

}
