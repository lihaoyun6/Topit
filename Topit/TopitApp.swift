//
//  TopitApp.swift
//  Topit
//
//  Created by apple on 2024/11/17.
//

import SwiftUI
import Cocoa
import Foundation
import ScreenCaptureKit
import KeyboardShortcuts

let ud = UserDefaults.standard
let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

var isMacOS13 = false
var isMacOS12 = false
var axPerm = false
var scPerm = false
var togglePinWindows = false

@main
struct TopitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .background(
                    WindowAccessor(
                        onWindowOpen: { w in
                            if let w = w {
                                w.level = .floating
                                w.titlebarSeparatorStyle = .none
                                guard let nsSplitView = findNSSplitVIew(view: w.contentView),
                                      let controller = nsSplitView.delegate as? NSSplitViewController else { return }
                                controller.splitViewItems.first?.canCollapse = false
                                controller.splitViewItems.first?.minimumThickness = 140
                                controller.splitViewItems.first?.maximumThickness = 140
                                w.orderFront(nil)
                            }
                        })
                )
        }.commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    @AppStorage("showOnDock") private var showOnDock: Bool = true
    @AppStorage("showMenubar") private var showMenubar: Bool = true
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        if #unavailable(macOS 14) { isMacOS13 = true }
        if #unavailable(macOS 13) { isMacOS12 = true }
        if showOnDock { NSApp.setActivationPolicy(.regular) }
        if let button = statusBarItem.button {
            button.target = self
            button.image = NSImage(named: "statusIcon")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Pin a Window".local, action: #selector(selectWindowToPin), keyEquivalent: "p")
        menu.addItem(withTitle: "Unpin all Windows".local, action: #selector(unPinAll), keyEquivalent: "u")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Window Selector".local, action: #selector(openFromMenuBar), keyEquivalent: "s")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…".local, action: #selector(settings), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for Updates…".local, action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Topit".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusBarItem.menu = menu
        statusBarItem.isVisible = showMenubar
        
        KeyboardShortcuts.onKeyDown(for: .unpinAll) { self.unPinAll() }
        KeyboardShortcuts.onKeyDown(for: .openMainPanel) { _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) }
        KeyboardShortcuts.onKeyDown(for: .selectWindow) { WindowHighlighter.shared.registerMouseMonitor() }
        KeyboardShortcuts.onKeyDown(for: .pinUnpin) { pnpUnderMouseWindow() }
        KeyboardShortcuts.onKeyDown(for: .pinUnpinTopmost) { pnpFrontmostWindow() }
        KeyboardShortcuts.onKeyDown(for: .togglePinWindows) {
            if togglePinWindows {
                togglePinWindows = false
                restoreFrontmostWindow()
            } else {
                togglePinWindows = true
                minimizeFrontmostWindow()
            }
        }
        
        tips("Topit uses the accessibility permissions\nand screen recording permissions\nto control and capture your windows.".local, id: "topit.how-to-use.note")
        tips("macOS will prevent any notifications from appearing while Topit is running\nIt's not a bug or Topit's fault!".local, id: "topit.no-notifications.note")
        scPerm = SCManager.updateAvailableContentSync() != nil
        axPerm = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as NSDictionary)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if showOnDock { _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if NSApp.windows.first(where: { $0.title == "Topit" })?.isVisible != true {
            axPerm = AXIsProcessTrusted()
            let mainPanel = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            if axPerm && scPerm { mainPanel.level = .floating }
            mainPanel.title = "Topit"
            mainPanel.titlebarSeparatorStyle = .none
            mainPanel.titlebarAppearsTransparent = true
            mainPanel.isMovableByWindowBackground = true
            mainPanel.toolbarStyle = .unifiedCompact
            let contentView = NSHostingView(rootView: ContentView())
            mainPanel.contentView = contentView
            mainPanel.makeKeyAndOrderFront(self)
            mainPanel.center()
        }
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unPinAll()
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Pin a Window".local, action: #selector(selectWindowToPin), keyEquivalent: "")
        menu.addItem(withTitle: "Unpin all Windows".local, action: #selector(unPinAll), keyEquivalent: "")
        return menu
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    @objc func unPinAll() {
        DispatchQueue.main.async {
            for layer in NSApp.windows.filter({$0.title.hasPrefix("Topit Layer")}) { layer.close() }
            AvoidManager.shared.activedFrame = .zero
        }
    }
    
    @objc func about() {
        openAboutPanel()
    }
    
    @objc func settings() {
        openSettingPanel()
    }
    
    @objc func openFromMenuBar() {
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    }
    
    @objc func selectWindowToPin() {
        WindowHighlighter.shared.registerMouseMonitor()
    }
}

func pnpUnderMouseWindow() {
    if let window = getWindowUnderMouse(), let windowID = window["kCGWindowNumber"] as? UInt32,
       let scWindow = getSCWindowWithID(windowID, noFilter: true), let scDisplay = getSCDisplayWithMouse() {
        if SCManager.pinnedWdinwows.contains(scWindow) {
            for w in NSApp.windows.filter({
                $0.title == "Topit Layer\(windowID)"
                || $0.title == "Topit Layer\(windowID)O"
            }) { w.close() }
        } else {
            closeMainWindow()
            createNewWindow(display: scDisplay, window: scWindow)
        }
    }
}

func pnpFrontmostWindow() {
    if let scWindow = getFrontmostWindow(), let scDisplay = getSCDisplayWithMouse() {
        let windowID = scWindow.windowID
        if SCManager.pinnedWdinwows.contains(scWindow) {
            for w in NSApp.windows.filter({
                $0.title == "Topit Layer\(windowID)"
                || $0.title == "Topit Layer\(windowID)O"
            }) { w.close() }
        } else {
            closeMainWindow()
            createNewWindow(display: scDisplay, window: scWindow)
        }
    }
}

func minimizeFrontmostWindow() {
    let pinnedWindows = SCManager.pinnedWdinwows
    for scWindow in pinnedWindows {
        let windowID = scWindow.windowID
        if let nsWindow = NSApp.windows.first(where: {
               $0.title == "Topit Layer\(windowID)" || $0.title == "Topit Layer\(windowID)O"
           }) {
            nsWindow.orderOut(nil)
        }
        minimizeOriginalWindow(windowID)
    }
}

func restoreFrontmostWindow() {
    let pinnedWindows = SCManager.pinnedWdinwows
    
    print(pinnedWindows.count)
    for scWindow in pinnedWindows {
        let windowID = scWindow.windowID
        if let nsWindow = NSApp.windows.first(where: {
               $0.title == "Topit Layer\(windowID)" || $0.title == "Topit Layer\(windowID)O"
           }) {
            nsWindow.makeKeyAndOrderFront(nil)
        }
        restoreOriginalWindow(windowID)
    }
}

func closeMainWindow() {
    NSApp.windows.first(where: { $0.title == "Topit" })?.close()
}

func openAboutPanel() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel()
}

func getMenuBarHeight() -> CGFloat {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    if let screen = screen {
        return screen.frame.height - screen.visibleFrame.height - (screen.visibleFrame.origin.y - screen.frame.origin.y) - 1
    }
    return 0.0
}

func tips(_ message: String, title: String? = nil, id: String, switchButton: Bool = false, width: Int? = nil, action: (() -> Void)? = nil) {
    let never = (ud.object(forKey: "neverRemindMe") as? [String]) ?? []
    if !never.contains(id) {
        if switchButton {
            let alert = createAlert(title: title ?? Bundle.main.appName + " Tips".local, message: message, button1: "OK", button2: "Don't remind me again", width: width).runModal()
            if alert == .alertSecondButtonReturn { ud.setValue(never + [id], forKey: "neverRemindMe") }
            if alert == .alertFirstButtonReturn { action?() }
        } else {
            let alert = createAlert(title: title ?? Bundle.main.appName + " Tips".local, message: message, button1: "Don't remind me again", button2: "OK", width: width).runModal()
            if alert == .alertFirstButtonReturn { ud.setValue(never + [id], forKey: "neverRemindMe") }
            if alert == .alertSecondButtonReturn { action?() }
        }
    }
}

func createAlert(level: NSAlert.Style = .warning, title: String, message: String, button1: String, button2: String = "", width: Int? = nil) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title.local
    alert.informativeText = message.local
    alert.addButton(withTitle: button1.local)
    if button2 != "" { alert.addButton(withTitle: button2.local) }
    alert.alertStyle = level
    if let width = width {
        alert.accessoryView = NSView(frame: NSMakeRect(0, 0, Double(width), 0))
    }
    return alert
}

func openSettingPanel() {
    closeMainWindow()
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 14, *) {
        NSApp.mainMenu?.items.first?.submenu?.item(at: 3)?.performAction()
    }else if #available(macOS 13, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

func findNSSplitVIew(view: NSView?) -> NSSplitView? {
    var queue = [NSView]()
    if let root = view { queue.append(root) }
    
    while !queue.isEmpty {
        let current = queue.removeFirst()
        if current is NSSplitView { return current as? NSSplitView }
        for subview in current.subviews { queue.append(subview) }
    }
    return nil
}

extension NSMenuItem {
    func performAction() {
        guard let menu else { return }
        menu.performActionForItem(at: menu.index(of: self))
    }
}

class NNSPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}

class EscPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        self.close()
        WindowHighlighter.shared.stopMouseMonitor()
    }
    override var canBecomeKey: Bool {
        return true
    }
}

extension Scene {
    func myWindowIsContentResizable() -> some Scene {
        if #available(macOS 13.0, *) {
            return self.windowResizability(.contentSize)
        }
        else {
            return self
        }
    }
}

extension Bundle {
    var appName: String {
        let appName = self.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                     ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                     ?? "Unknown App Name"
        return appName
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    var isMainScreen: Bool {
        guard let id = self.displayID else { return false }
        return (CGDisplayIsMain(id) == 1)
    }
}

extension SCDisplay {
    var nsScreen: NSScreen? {
        return NSScreen.screens.first(where: { $0.displayID == self.displayID })
    }
}

extension String {
    var local: String { return NSLocalizedString(self, comment: "") }
}
