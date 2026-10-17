import AppKit
import ApplicationServices
import Darwin

/// Transfer real keyboard/IME focus, preserving the source window's ordering.
/// Keystrokes subsequently travel through macOS once; Topit never copies them.
enum RegionNativeFocus {
    private typealias ProcessForPID = @convention(c) (Int32, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias SetFront = @convention(c) (UnsafePointer<UInt64>, UInt32, UInt32) -> Int32
    private typealias PostRecord = @convention(c) (UnsafePointer<UInt64>, UnsafePointer<UInt8>) -> Int32
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(library, name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }
    private static let processForPID = symbol("GetProcessForPID").map { unsafeBitCast($0, to: ProcessForPID.self) }
    private static let setFront = symbol("_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFront.self) }
    private static let postRecord = symbol("SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostRecord.self) }
    private typealias AXWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let axWindowID = symbol("_AXUIElementGetWindow").map { unsafeBitCast($0, to: AXWindowID.self) }
    private static var session = RegionFocusSession()

    static func begin(windowID: CGWindowID, processID: pid_t) -> Bool {
        guard AXIsProcessTrusted(),
              let window = getCGWindowWithID(windowID), window[kCGWindowOwnerPID as String] as? pid_t == processID else { return false }
        let current = focusedTarget()
        let target = RegionFocusTarget(windowID: windowID, processID: processID)
        return session.begin(target, current: current) { focus($0, current: current) }
    }

    static func end(windowID: CGWindowID, processID: pid_t) {
        let current = focusedTarget()
        guard let prior = session.end(RegionFocusTarget(windowID: windowID, processID: processID), current: current),
              ownsWindow(prior) else { return }
        _ = focus(prior, current: current)
    }

    private static func ownsWindow(_ target: RegionFocusTarget) -> Bool {
        guard let window = getCGWindowWithID(target.windowID) else { return false }
        return window[kCGWindowOwnerPID as String] as? pid_t == target.processID
    }

    /// Use the actual key window, not the first window in display order: a source
    /// can be focused while covered, and an app may own several normal windows.
    private static func focusedTarget() -> RegionFocusTarget? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let axWindowID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let window = unsafeBitCast(value, to: AXUIElement.self)
            var id: CGWindowID = 0
            guard axWindowID(window, &id) == .success, id != 0 else { continue }
            let target = RegionFocusTarget(windowID: id, processID: pid)
            if ownsWindow(target) { return target }
        }
        return nil
    }

    private static func focus(_ target: RegionFocusTarget, current: RegionFocusTarget?) -> Bool {
        let windowID = target.windowID
        let processID = target.processID
        guard let processForPID, let setFront, let postRecord else { return false }
        return RegionFocusHandoff.perform(windowID: windowID, processID: processID,
            focusedWindowID: current?.processID == processID ? current?.windowID : nil, process: { pid in
            var psn: UInt64 = 0
            return processForPID(pid, &psn) == 0 ? psn : nil
        }, activate: { serial, window in
            var serial = serial
            // kCPSUserGenerated; unlike AXRaise this sets input focus without ordering.
            return setFront(&serial, window, 0x200) == 0
        }, post: { serial, record in
            var serial = serial
            return record.withUnsafeBufferPointer { bytes in postRecord(&serial, bytes.baseAddress!) == 0 }
        })
    }
}
