import AppKit
import ApplicationServices
import OSLog

/// Sends input to the source window, without moving it or making the entire window float.
final class RegionInputRouter {
    let windowID: CGWindowID
    let processID: pid_t
    let region: CGRect
    var onFocusFailure: (() -> Void)?
    private let logger = Logger(subsystem: "com.lihaoyun6.Topit", category: "RegionInput")
    private var diagnosticClicksRemaining = 8
    private var pressedButtons = Set<Int>()
    private var backgroundButtons = Set<Int>()
    private var lastPoint = CGPoint.zero

    init(windowID: CGWindowID, processID: pid_t, region: CGRect) {
        self.windowID = windowID
        self.processID = processID
        self.region = region
    }

    func mouse(_ event: NSEvent, point: CGPoint, viewSize: CGSize) {
        guard processID > 0, AXIsProcessTrusted(), let frame = getCGWindowFrameWithID(windowID),
              let mapped = RegionGeometry.sourcePoint(point, viewSize: viewSize, region: region, sourceFrame: frame) else { return }
        lastPoint = mapped
        // AXPress is deliberately excluded: the target app may activate itself when
        // handling an accessibility action, even if Topit never requests activation.
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            observeSourceOrdering()
        }
        if event.type == .leftMouseDown {
            guard RegionNativeFocus.begin(windowID: windowID, processID: processID) else {
                onFocusFailure?()
                return
            }
            // Only the original control receives focus. No text values are copied.
            _ = RegionTextFocus.focus(at: mapped, windowID: windowID, processID: processID)
        }
        postMouse(event, at: mapped, frame: frame)
    }

    private func postMouse(_ event: NSEvent, at point: CGPoint, frame: CGRect) {
        let downTypes: Set<NSEvent.EventType> = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let upTypes: Set<NSEvent.EventType> = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        if upTypes.contains(event.type), !pressedButtons.contains(event.buttonNumber) { return }
        let copy: CGEvent?
        if event.type == .scrollWheel {
            copy = event.cgEvent?.copy()
        } else {
            if event.type == .leftMouseDown {
                let inactive = !sourceIsFrontmost
                if inactive || !windowsAboveSource().isEmpty { backgroundButtons.insert(event.buttonNumber) }
            }
            copy = RegionEventFactory.mouse(event, windowID: windowID, processID: processID,
                                            point: point, sourceFrame: frame,
                                            keepInBackground: backgroundButtons.contains(event.buttonNumber),
                                            preventWindowOrdering: backgroundButtons.contains(event.buttonNumber))
        }
        guard let copy else { return }
        guard RegionEventFactory.targetPointer(copy, windowID: windowID, processID: processID,
                                               point: point, sourceFrame: frame) else { return }
        copy.postToPid(processID)
        if downTypes.contains(event.type) { pressedButtons.insert(event.buttonNumber) }
        if upTypes.contains(event.type) {
            pressedButtons.remove(event.buttonNumber)
            backgroundButtons.remove(event.buttonNumber)
        }
    }

    /// Only pointer gestures are synthesized. Keyboard input belongs to macOS.
    func releaseInput() {
        for button in pressedButtons {
            let type: CGEventType = button == 0 ? .leftMouseUp : (button == 1 ? .rightMouseUp : .otherMouseUp)
            if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: lastPoint,
                                   mouseButton: CGMouseButton(rawValue: UInt32(button)) ?? .left) {
                if backgroundButtons.contains(button) {
                    event.flags.insert(.maskCommand)
                    event.setIntegerValueField(.mouseEventSubtype, value: 3)
                }
                if let frame = getCGWindowFrameWithID(windowID),
                   RegionEventFactory.targetPointer(event, windowID: windowID, processID: processID,
                                                    point: lastPoint, sourceFrame: frame) {
                    event.postToPid(processID)
                }
            }
        }
        pressedButtons.removeAll()
        backgroundButtons.removeAll()
    }

    private var sourceIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
    }

    func endNativeInput() {
        releaseInput()
        RegionNativeFocus.end(windowID: windowID, processID: processID)
    }

    /// Record only IDs and ordering, never titles, pixels, key codes, or input text.
    /// A source app can still choose to activate itself in its own event handler.
    private func observeSourceOrdering() {
        guard diagnosticClicksRemaining > 0 else { return }
        diagnosticClicksRemaining -= 1
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let above = windowsAboveSource()
        logger.info("pid-targeted click source=\(self.processID) window=\(self.windowID) foreground=\(before)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let after = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let crossed = !above.subtracting(self.windowsAboveSource()).isEmpty
            if crossed {
                self.logger.notice("Source ordering changed after pid-targeted input source=\(self.processID) activated=\(after == self.processID) crossedWindow=\(crossed)")
            }
        }
    }

    private func windowsAboveSource() -> Set<CGWindowID> {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, windowID) as? [[String: Any]] else { return [] }
        return Set(windows.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowOwnerPID as String] as? pid_t != getpid(),
                  let id = info[kCGWindowNumber as String] as? CGWindowID, id != windowID else { return nil }
            return id
        })
    }
}
