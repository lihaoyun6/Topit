import AppKit
import ApplicationServices

/// Focus an editable control at the requested source point without pressing it
/// or asking the application/window to come to the front.
enum RegionTextFocus {
    static func focus(at point: CGPoint, windowID: CGWindowID, processID: pid_t) -> Bool {
        guard processID > 0, let source = getCGWindowWithID(windowID),
              source[kCGWindowOwnerPID as String] as? pid_t == processID,
              let sourceFrame = getCGWindowFrame(window: source) else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.04)
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.count <= 32 else { return false }
        var matching = [AXUIElement]()
        for window in windows {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            if frame(window) == sourceFrame { matching.append(window) }
        }
        guard matching.count == 1, let sourceWindow = matching.first else { return false }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }

        // Chromium sometimes hit-tests the composer's AXGroup instead of its
        // contenteditable AXTextArea. Search only the point-containing branches
        // around that hit, bounded to avoid walking an entire conversation.
        var roots = [hit]
        var ancestor = hit
        for _ in 0..<6 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard let parent = element(ancestor, kAXParentAttribute),
                  !CFEqual(parent, sourceWindow),
                  string(parent, kAXRoleAttribute) != kAXApplicationRole else { break }
            roots.append(parent)
            ancestor = parent
        }
        var visited = [AXUIElement]()
        var candidates = [(AXUIElement, CGFloat)]()
        for root in roots {
            var queue = [root]
            while !queue.isEmpty && visited.count < 64 && ProcessInfo.processInfo.systemUptime < deadline {
                let candidate = queue.removeFirst()
                if visited.contains(where: { CFEqual($0, candidate) }) { continue }
                visited.append(candidate)
                let rect = frame(candidate)
                if let rect, !rect.contains(point) { continue }
                if let role = string(candidate, kAXRoleAttribute),
                   [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
                   let rect, rect.width > 0, rect.height > 0,
                   let window = element(candidate, kAXWindowAttribute), CFEqual(window, sourceWindow),
                   value(candidate, kAXEnabledAttribute) as? Bool != false {
                    candidates.append((candidate, rect.width * rect.height))
                }
                queue.append(contentsOf: value(candidate, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            }
        }
        for (candidate, _) in candidates.sorted(by: { $0.1 < $1.1 }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(candidate, kAXFocusedAttribute as CFString, &settable) == .success,
                  settable.boolValue,
                  AXUIElementSetAttributeValue(candidate, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { continue }
            if let focused = element(app, kAXFocusedUIElementAttribute), CFEqual(focused, candidate) { return true }
        }
        return false
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(source, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(result, to: AXUIElement.self)
    }

    private static func string(_ source: AXUIElement, _ attribute: String) -> String? {
        value(source, attribute) as? String
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
