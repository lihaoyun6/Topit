import Foundation

struct RegionFocusTarget: Equatable {
    let windowID: UInt32
    let processID: Int32
}

/// Keeps restoration scoped to one uninterrupted source-focus interaction.
struct RegionFocusSession {
    private(set) var active: RegionFocusTarget?
    private(set) var previous: RegionFocusTarget?

    mutating func begin(_ target: RegionFocusTarget, current: RegionFocusTarget?,
                        focus: (RegionFocusTarget) -> Bool) -> Bool {
        let restore = active != nil && current == active ? previous : current
        guard focus(target) else { return false }
        previous = restore == target ? nil : restore
        active = target
        return true
    }

    mutating func end(_ target: RegionFocusTarget, current: RegionFocusTarget?) -> RegionFocusTarget? {
        guard active == target else { return nil }
        let restore = previous
        previous = nil
        active = nil
        return current == target ? restore : nil
    }
}
