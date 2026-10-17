import Foundation
import CoreGraphics

/// Recognizes two isolated Control taps. Chords, clicks and long holds cancel it.
struct RegionAutoHideGesture {
    private var controlDown = false
    private var pressedAt: TimeInterval?
    private var previousRelease: TimeInterval?
    private var lastTimestamp: TimeInterval?

    mutating func modifiersChanged(control: Bool, otherModifiers: Bool, timestamp: TimeInterval) -> Bool {
        if let lastTimestamp, timestamp < lastTimestamp { reset() }
        lastTimestamp = timestamp
        if otherModifiers { cancel() }
        guard control != controlDown else {
            // Both Control keys held together must not count as two taps.
            if control { cancel() }
            return false
        }
        controlDown = control
        if control {
            pressedAt = otherModifiers ? nil : timestamp
            return false
        }
        defer { pressedAt = nil }
        guard !otherModifiers, let pressedAt, timestamp - pressedAt <= 0.3 else {
            previousRelease = nil
            return false
        }
        if let previousRelease, timestamp - previousRelease <= 0.4 {
            self.previousRelease = nil
            return true
        }
        previousRelease = timestamp
        return false
    }

    mutating func cancel() {
        pressedAt = nil
        previousRelease = nil
    }

    mutating func reset() {
        cancel()
        controlDown = false
        lastTimestamp = nil
    }
}

enum RegionAutoHideVisibility {
    static func shouldHide(pointer: CGPoint, frame: CGRect, currentlyHidden: Bool) -> Bool {
        // A wider exit margin prevents flicker along the edge of a hidden panel.
        let margin: CGFloat = currentlyHidden ? 30 : 18
        return frame.insetBy(dx: -margin, dy: -margin).contains(pointer)
    }
}
