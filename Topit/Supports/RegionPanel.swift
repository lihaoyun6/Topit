import AppKit

final class RegionPanel: NSPanel {
    var onCancel: (() -> Void)?
    var allowsInteraction = true
    var allowsKeyboardFocus = false
    override var canBecomeKey: Bool { allowsInteraction && allowsKeyboardFocus }
    override func cancelOperation(_ sender: Any?) { if allowsInteraction { onCancel?() } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard allowsInteraction else { return false }
        return super.performKeyEquivalent(with: event)
    }
}
