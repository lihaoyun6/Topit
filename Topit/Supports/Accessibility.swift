//
//  Accessibility.swift
//  Topit
//
//  Created by apple on 2024/11/18.
//

import SwiftUI
import ScreenCaptureKit

var minimizedAXWindows: [CGWindowID: AXUIElement] = [:]

func getScreenWithMouse() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    return screenWithMouse
}

func getSCWindowWithID(_ windowID: UInt32?, noFilter: Bool = false) -> SCWindow? {
    guard let windowID else { return nil }
    _ = SCManager.updateAvailableContentSync()
    let windows = SCManager.getWindows(noFilter: noFilter)
    return windows.first(where: { $0.windowID == windowID })
}

func getSCDisplayWithMouse() -> SCDisplay? {
    if let displays = SCManager.availableContent?.displays {
        for display in displays {
            if let currentDisplayID = getScreenWithMouse()?.displayID {
                if display.displayID == currentDisplayID {
                    return display
                }
            }
        }
    }
    return nil
}

func getAppIcon(_ app: SCRunningApplication) -> NSImage? {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 69, height: 69)
        return icon
    }
    let icon = NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: "blank icon")
    icon!.size = NSSize(width: 69, height: 69)
    return icon
}

func createNewWindow(display: SCDisplay, window: SCWindow, opacity: Double? = nil) {
    let title = "Topit Layer\(window.windowID)\(opacity == nil ? "" : "O")"
    var panel: NSWindow!
    var contentView: NSView!
    
    if let p = NSApp.windows.first(where: { $0.title == title }) {
        panel = p
    } else {
        panel = NNSPanel(contentRect: CGRectTransform(cgRect: window.frame), styleMask: [.closable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    }
    
    panel.hasShadow = true
    
    if #unavailable(macOS 13) {
        contentView = NSHostingView(rootView: OverlayView12(display: display, window: window))
    } else {
        if let opacity = opacity {
            panel.hasShadow = false
            contentView = NSHostingView(rootView: OverlayViewOpacity(display: display, window: window, Opacity: opacity))
        } else {
            contentView = NSHostingView(rootView: OverlayView(display: display, window: window))
        }
    }
    panel.contentView = contentView
    panel.title = title
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = false
    panel.isReleasedWhenClosed = false
    panel.makeKeyAndOrderFront(nil)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        panel.setFrame(CGRectTransform(cgRect: window.frame), display: true)
        if let id = window.owningApplication?.bundleIdentifier {
            NSApp.activate(ignoringOtherApps: true)
            bringAppToFront(bundleIdentifier: id)
        }
    }
}

func getAllCGWindows() -> [[String: Any]]? {
    guard var windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements,.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    
    windowList = windowList.filter({
        !["SystemUIServer", "Window Server"].contains($0["kCGWindowOwnerName"] as? String)
        && $0["kCGWindowAlpha"] as? NSNumber != 0
        && $0["kCGWindowLayer"] as? NSNumber == 0
    })
    
    return windowList
}

func getFrontmostWindow() -> SCWindow? {
    guard let appID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    guard var windowList = getAllCGWindows() else { return nil }
    
    windowList = windowList.filter({
        guard let frame = getCGWindowFrame(window: $0) else { return false }
        return $0["kCGWindowOwnerPID"] as? pid_t == appID
        && $0["kCGWindowAlpha"] as? NSNumber != 0
        && $0["kCGWindowLayer"] as? NSNumber == 0
        && frame.width > 40 && frame.height > 40
    })
    if let window = windowList.first {
        return getSCWindowWithID(window["kCGWindowNumber"] as? UInt32, noFilter: true)
    }
    return nil
}

func isFrontmostWindow(appID: pid_t?, windowID: UInt32) -> Bool {
    guard let appID = appID, var windowList = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, windowID) as? [[String: Any]] else {
        return false
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != appID { return false }

    windowList = windowList.filter({
        $0["kCGWindowOwnerPID"] as? pid_t == appID
        && $0["kCGWindowAlpha"] as? NSNumber != 0
        && $0["kCGWindowLayer"] as? NSNumber == 0
    })
    if #available(macOS 14, *) { windowList.removeFirst() }
    if let window = windowList.first {
        if let wid = window["kCGWindowNumber"] as? UInt32, wid == windowID { return true }
    }
    return false
}

func getWindowUnderMouse() -> [String: Any]? {
    let mousePosition = NSEvent.mouseLocation
    guard let windowList = getAllCGWindows() else { return nil }

    for window in windowList {
        guard let bounds = getCGWindowFrame(window: window) else { continue }
        if CGRectTransform(cgRect: bounds).contains(mousePosition) {
            return window
        }
    }
    return nil
}

func CGRectTransform(cgRect: CGRect) -> NSRect {
    let x = cgRect.origin.x
    let y = cgRect.origin.y
    let w = cgRect.width
    let h = cgRect.height
    if let main = NSScreen.screens.first(where: { $0.isMainScreen }) {
        return NSRect(x: x, y: main.frame.height - y - h, width: w, height: h)
    }
    return cgRect
}

func CGPointTransform(cgPoint: CGPoint, mainHeight: CGFloat) -> NSPoint {
    let x = cgPoint.x
    let y = cgPoint.y
    return NSPoint(x: x, y: mainHeight - y)
}

func bringAppToFront(bundleIdentifier: String) {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
        app.activate(options: [.activateIgnoringOtherApps])
    } else {
        print("Application not found.")
    }
}

func isWindowOnTop(windowID: CGWindowID) -> Bool {
    guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, windowID) as? [[String: Any]] else {
        return false
    }
    return windowList.isEmpty
}

func getCGWindowFrame(window: [String: Any]) -> CGRect? {
    guard let boundsDict = window["kCGWindowBounds"] as? [String: CGFloat] else { return nil }
    let bounds = CGRect(
        x: boundsDict["X"] ?? 0,
        y: boundsDict["Y"] ?? 0,
        width: boundsDict["Width"] ?? 0,
        height: boundsDict["Height"] ?? 0
    )
    return bounds
}

func getCGWindowFrameWithID(_ windowID: CGWindowID) -> CGRect? {
    guard let cgWindows = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else {
        return nil
    }
    if let cgWindow = cgWindows.first, let bounds = getCGWindowFrame(window: cgWindow) {
        return bounds
    }
    return nil
}

func getCGWindowWithID(_ windowID: CGWindowID) -> [String: Any]? {
    guard let cgWindows = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
          let cgWindow = cgWindows.first else {
        return nil
    }
    return cgWindow
}

func getAXWindow(windowID: CGWindowID) -> AXUIElement? {
    guard let cgWindows = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
          let cgWindow = cgWindows.first else {
        return nil
    }

    // 获取窗口的进程 ID
    guard let pid = cgWindow["kCGWindowOwnerPID"] as? pid_t else {
        print("Failed to retrieve PID for CGWindow.")
        return nil
    }

    // 创建应用的 AXUIElement
    let appElement = AXUIElementCreateApplication(pid)
    var appWindows: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &appWindows)
    guard result == .success, let windows = appWindows as? [AXUIElement] else {
        print("Failed to retrieve AXUIElement windows for application.")
        return nil
    }
    
    guard let cgWindowFrame = getCGWindowFrame(window: cgWindow) else { return nil }
    //let cgWindowTitle = cgWindow["kCGWindowName"] as? String
    
    // 匹配窗口的 AXUIElement
    for axWindow in windows {
        //检查标题
        //var title: CFTypeRef?
        //AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &title)
        //let axTitle = title as? String

        // 检查位置和尺寸
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var axPosition = CGPoint.zero
        var axSize = CGSize.zero

        if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success {
            let position = positionValue as! AXValue
            AXValueGetValue(position, .cgPoint, &axPosition)
        }

        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success {
            let size = sizeValue as! AXValue
            AXValueGetValue(size, .cgSize, &axSize)
        }

        let axFrame = CGRect(origin: axPosition, size: axSize)

        // 同时匹配标题、位置和尺寸
        //if axTitle == cgWindowTitle, axFrame.equalTo(cgWindowFrame) { return axWindow }
        if axFrame.equalTo(cgWindowFrame) { return axWindow }
    }

    print("No matching AXUIElement found!")
    return nil
}

func activateWindow(axWindow: AXUIElement?, frame: CGRect) {
    if let axWindow = axWindow {
        let position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        moveAxWindow(axWindow: axWindow, origin: position)
        
        let size = CGSize(width: frame.width, height: frame.height)
        resizeAxWindow(axWindow: axWindow, size: size)
        
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }
}

func moveAxWindow(axWindow: AXUIElement?, origin: CGPoint) {
    if let axWindow = axWindow {
        var position = CGPoint(x: origin.x, y: origin.y)
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, AXValue.from(point: &position))
    }
}

func resizeAxWindow(axWindow: AXUIElement?, size: CGSize) {
    if let axWindow = axWindow {
        var size = CGSize(width: size.width, height: size.height)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, AXValue.from(size: &size))
    }
}

func closeAXWindow(_ axWindow: AXUIElement?) -> Bool {
    guard let axWindow = axWindow else { return false }
    
    var closeButtonRef: CFTypeRef?
    let closeButtonResult = AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef)
    guard closeButtonResult == .success, let closeButton = closeButtonRef else { return false }
    let closeActionResult = AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
    if closeActionResult == .success { return true }
    print("Failed to close the window!")
    return false
}

/// 尝试将给定 `windowID` 的窗口最小化 (前提：有辅助功能权限，且应用支持 AXMinimized)
func minimizeOriginalWindow(_ windowID: CGWindowID) {
    // 1. 找到该 windowID 对应的进程 PID、然后拿到 AXUIElement
    guard let axWindow = getAXWindow(windowID: windowID) else {
        print("Failed to retrieve AXWindow for windowID \(windowID)")
        return
    }
    minimizedAXWindows[windowID] = axWindow
    // 2. 设置 AXMinimized = true
    let result = AXUIElementSetAttributeValue(
        axWindow,
        kAXMinimizedAttribute as CFString,
        kCFBooleanTrue
    )
    if result != .success {
        print("Failed to minimize window \(windowID). Result: \(result.rawValue)")
    } else {
        print("Window \(windowID) minimized successfully.")
    }
}

/// 还原窗口 (取消最小化)
func restoreOriginalWindow(_ windowID: CGWindowID) {
    // 1. 从字典拿到 AXWindow 引用
    guard let axWindow = minimizedAXWindows[windowID] else {
        print("We don't have AXUIElement cached for windowID \(windowID).")
        return
    }
    let result = AXUIElementSetAttributeValue(
        axWindow,
        kAXMinimizedAttribute as CFString,
        kCFBooleanFalse
    )
    if result != .success {
        print("Failed to restore window \(windowID). Result: \(result.rawValue)")
    } else {
        print("Window \(windowID) restored successfully.")
    }
}

// AXValue 扩展，便于设置值
extension AXValue {
    static func from(point: inout CGPoint) -> AXValue {
        return AXValueCreate(.cgPoint, &point)!
    }

    static func from(size: inout CGSize) -> AXValue {
        return AXValueCreate(.cgSize, &size)!
    }
}
