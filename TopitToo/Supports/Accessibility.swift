//
//  Accessibility.swift
//  TopitToo
//
//  Created by apple on 2024/11/18.
//

import SwiftUI
import ScreenCaptureKit

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
    let title = "TopitToo Layer\(window.windowID)\(opacity == nil ? "" : "O")"
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

/// Get the close button center position in overlay-local coordinates (top-left origin, y-down).
/// Returns nil if AXUIElement cannot access the close button (e.g. Electron/Java apps).
func getCloseButtonLocalCenter(windowFrame: CGRect, mainScreenHeight: CGFloat, axWindow: AXUIElement?) -> CGPoint? {
    guard let axWindow = axWindow else {
        print("[Topit][AX DEBUG] axWindow is nil")
        return nil
    }

    // Debug: get AXWindow's own position to understand coordinate system
    var axWindowPosValue: CFTypeRef?
    var axWindowPos = CGPoint.zero
    if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &axWindowPosValue) == .success {
        let pos = axWindowPosValue as! AXValue
        AXValueGetValue(pos, .cgPoint, &axWindowPos)
        print("[Topit][AX DEBUG] AXWindow position=(\(axWindowPos.x), \(axWindowPos.y))")
    }

    var closeButtonRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef)
    guard result == .success, let closeButton = closeButtonRef else {
        print("[Topit] AX close button not available (AXError=\(result.rawValue)), using estimated position")
        // Fallback for Electron/custom-chrome apps: estimate standard macOS traffic light position
        // Close button center ~20pt from window top-left in overlay-local coords
        return CGPoint(x: 20, y: 20)
    }

    let closeButtonElement = closeButton as! AXUIElement

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    var axPosition = CGPoint.zero
    var axSize = CGSize.zero

    let posResult = AXUIElementCopyAttributeValue(closeButtonElement, kAXPositionAttribute as CFString, &positionValue)
    let sizeResult = AXUIElementCopyAttributeValue(closeButtonElement, kAXSizeAttribute as CFString, &sizeValue)
    if posResult != .success || sizeResult != .success {
        print("[Topit][AX DEBUG] Close button position/size failed, posResult=\(posResult.rawValue), sizeResult=\(sizeResult.rawValue)")
        return nil
    }

    let position = positionValue as! AXValue
    AXValueGetValue(position, .cgPoint, &axPosition)
    let size = sizeValue as! AXValue
    AXValueGetValue(size, .cgSize, &axSize)

    // AX coords use screen top-left origin (y-down), same as NSWindow coords
    // Overlay-local: overlay top-left origin, y-down
    // Overlay frame == windowFrame (CGWindow)
    let buttonCenterX = axPosition.x - windowFrame.origin.x + axSize.width / 2
    // AX position is screen top-left origin (y-down), same as NSWindow coords
    // Convert to overlay-local (top-left origin, y-down): subtract window top-left
    let buttonCenterY = axPosition.y - windowFrame.origin.y + axSize.height / 2


    print("[Topit] AX close button detected — axPosition=(\(axPosition.x), \(axPosition.y)), axSize=(\(axSize.width), \(axSize.height)), overlay-local=(\(buttonCenterX), \(buttonCenterY)), windowFrame=origin=(\(windowFrame.origin.x), \(windowFrame.origin.y)) size=(\(windowFrame.width), \(windowFrame.height)) mainScreenHeight=\(mainScreenHeight)")
    return CGPoint(x: buttonCenterX, y: buttonCenterY)
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
