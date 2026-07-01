//
//  AppleScript.swift
//  TopitToo
//
//  Created by apple on 2024/12/1.
//

import AppKit
import Foundation

class selectWindow: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        WindowHighlighter.shared.registerMouseMonitor()
    }
}

class showSelector: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        AppDelegate.shared.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    }
}

class pnpFront: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { pnpFrontmostWindow() }
}

class pnpMouse: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { pnpUnderMouseWindow() }
}

class unpinAllWindows: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            for layer in NSApp.windows.filter({$0.title.hasPrefix("TopitToo Layer")}) { layer.close() }
            AvoidManager.shared.activedFrame = .zero
        }
    }
}
