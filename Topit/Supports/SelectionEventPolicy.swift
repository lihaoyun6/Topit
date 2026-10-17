import AppKit

enum SelectionEventPolicy {
    static func cancelsSelection(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 53
    }
}
