import Foundation

/// Key-window notifications used by macOS's process-focus SPI (also used by yabai).
/// No mouse/key payload and no AXRaise action are generated here.
enum RegionFocusHandoff {
    private static func activationRecord(windowID: UInt32, active: Bool) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 0xf8)
        record[0x04] = 0xf8
        record[0x08] = 0x0d
        record[0x8a] = active ? 1 : 2
        var window = windowID
        withUnsafeBytes(of: &window) { record.replaceSubrange(0x3c..<0x40, with: $0) }
        return record
    }

    static func records(windowID: UInt32) -> [[UInt8]] {
        var record = [UInt8](repeating: 0, count: 0xf8)
        record[0x04] = 0xf8
        record[0x3a] = 0x10
        var window = windowID
        withUnsafeBytes(of: &window) { bytes in
            record.replaceSubrange(0x3c..<0x40, with: bytes)
        }
        record.replaceSubrange(0x20..<0x30, with: repeatElement(UInt8(0xff), count: 0x10))
        record[0x08] = 0x01
        let first = record
        record[0x08] = 0x02
        return [first, record]
    }

    static func perform(windowID: UInt32, processID: Int32,
                        focusedWindowID: UInt32? = nil,
                        process: (Int32) -> UInt64?, activate: (UInt64, UInt32) -> Bool,
                        post: (UInt64, [UInt8]) -> Bool,
                        waitForDeactivation: () -> Void = { Thread.sleep(forTimeInterval: 0.04) }) -> Bool {
        guard windowID != 0, processID > 0, focusedWindowID != 0,
              let psn = process(processID) else { return false }
        var needsRecovery = false
        defer {
            if needsRecovery, let focusedWindowID {
                // A partially delivered handoff must not leave the existing
                // window deactivated. This only restores focus, never text.
                _ = post(psn, activationRecord(windowID: focusedWindowID, active: true))
                _ = activate(psn, focusedWindowID)
                for record in records(windowID: focusedWindowID) { _ = post(psn, record) }
            }
        }
        if let focusedWindowID {
            guard post(psn, activationRecord(windowID: focusedWindowID, active: false)) else { return false }
            needsRecovery = true
            // Matches the native same-process window handoff. Some applications
            // drop the activation when both notices arrive instantaneously.
            waitForDeactivation()
            guard post(psn, activationRecord(windowID: windowID, active: true)) else { return false }
        }
        guard activate(psn, windowID) else { return false }
        for record in records(windowID: windowID) {
            guard post(psn, record) else { return false }
        }
        needsRecovery = false
        return true
    }
}
