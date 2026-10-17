import Foundation

@main
struct RegionFocusHandoffTests {
    static func main() {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures += 1; print("FAIL \(label)") }
        }
        var lookups = [Int32]()
        var activations = [(UInt64, UInt32)]()
        var posted = [(UInt64, [UInt8])]()
        func perform(_ window: UInt32 = 0x12345678, _ pid: Int32 = 456) -> Bool {
            RegionFocusHandoff.perform(windowID: window, processID: pid,
                process: { lookups.append($0); return 0xabcdef01 },
                activate: { activations.append(($0, $1)); return true },
                post: { posted.append(($0, $1)); return true })
        }
        check(perform(), "native focus handoff succeeds")
        check(lookups == [456], "only the requested process is resolved once")
        check(activations.count == 1 && activations[0].1 == 0x12345678, "one system focus request targets the source window")
        check(posted.count == 2 && posted.allSatisfy { $0.0 == 0xabcdef01 }, "exactly one balanced key-window notification pair")
        for (index, pair) in posted.enumerated() {
            let bytes = pair.1
            check(bytes.count == 0xf8 && bytes[4] == 0xf8, "native record length is encoded")
            check(bytes[8] == UInt8(index + 1) && bytes[0x3a] == 0x10, "key-window event ordering is preserved")
            let window = bytes[0x3c..<0x40].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            check(window == 0x12345678, "native-endian source window identifier survives encoding")
            check(bytes[0x20..<0x30].allSatisfy { $0 == 0xff }, "window-focus record marker retained")
        }
        let before = (lookups.count, activations.count, posted.count)
        check(!perform(0) && !perform(123, 0) && !perform(123, -1), "invalid process/window cannot receive focus")
        check(before.0 == lookups.count && before.1 == activations.count && before.2 == posted.count, "invalid input has no side effects")
        check(!RegionFocusHandoff.perform(windowID: 1, processID: 1, process: { _ in nil }, activate: { _,_ in fatalError() }, post: { _,_ in fatalError() }), "missing process aborts before activation")
        var count = 0
        check(!RegionFocusHandoff.perform(windowID: 1, processID: 1, process: { _ in 1 }, activate: { _,_ in false }, post: { _,_ in count += 1; return true }) && count == 0, "focus failure never posts input")
        check(!RegionFocusHandoff.perform(windowID: 1, processID: 1, process: { _ in 1 }, activate: { _,_ in true }, post: { _,_ in count += 1; return false }) && count == 1, "failed notification is not retried or duplicated")

        // An already-frontmost process needs its old window deactivated before
        // the captured window is activated. Also repair the same-window case:
        // a nonactivating panel may have taken key focus from that window.
        for oldWindow: UInt32 in [20, 21] {
            var sequence = [String]()
            let succeeded = RegionFocusHandoff.perform(windowID: 21, processID: 100,
                focusedWindowID: oldWindow,
                process: { _ in 7 },
                activate: { _, _ in sequence.append("front"); return true },
                post: { _, record in
                    let id = record[0x3c..<0x40].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                    sequence.append("\(record[8]):\(record[0x8a]):\(id)")
                    return true
                }, waitForDeactivation: { sequence.append("wait") })
            check(succeeded && sequence == ["13:2:\(oldWindow)", "wait", "13:1:21", "front", "1:0:21", "2:0:21"],
                  "same-process focus must deliver ordered deactivation and activation for old window \(oldWindow)")
        }
        for failureStep in 1...5 {
            var steps = 0
            var finalWindow: UInt32 = 0
            var lastRecords = [UInt8]()
            let succeeded = RegionFocusHandoff.perform(windowID: 21, processID: 100, focusedWindowID: 20,
                process: { _ in 7 },
                activate: { _, window in steps += 1; finalWindow = window; return steps != failureStep },
                post: { _, record in steps += 1; lastRecords.append(record[8]); return steps != failureStep },
                waitForDeactivation: {})
            check(!succeeded, "partial native handoff failure \(failureStep) is reported")
            if failureStep > 1 {
                check(finalWindow == 20 && lastRecords.suffix(3) == [13, 1, 2],
                      "partial handoff failure \(failureStep) reactivates the original window")
            } else {
                check(steps == 1, "a rejected initial deactivation has no further side effects")
            }
        }
        var invalidCalls = 0
        check(!RegionFocusHandoff.perform(windowID: 21, processID: 100, focusedWindowID: 0,
            process: { _ in invalidCalls += 1; return 7 }, activate: { _,_ in true }, post: { _,_ in true }) && invalidCalls == 0,
              "unknown same-process window is rejected before native calls")
        if failures > 0 { exit(1) }
        print("Passed \(checks) native focus protocol checks")
    }
}
