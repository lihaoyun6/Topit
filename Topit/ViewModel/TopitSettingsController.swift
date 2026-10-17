import AppKit
import SwiftUI

/// All settings entry points share one native host. No menu-index lookup or split-view mutation.
final class TopitSettingsController {
    static let shared = TopitSettingsController()
    private var window: NSWindow?

    func show() {
        WindowHighlighter.shared.stopMouseMonitor()
        RegionPinManager.shared.cancelSelection()
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 500),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.identifier = NSUserInterfaceItemIdentifier("TopitSettingsWindow")
            panel.title = "Topit Settings".local
            panel.contentViewController = host
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.level = .floating
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
