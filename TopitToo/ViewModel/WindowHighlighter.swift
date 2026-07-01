//
//  WindowHighlighter.swift
//  TopitToo
//
//  Created by apple on 2024/11/26.
//

import SwiftUI

struct CoverView: View {
    var body: some View {
        Color.clear.overlay { Rectangle().stroke(.blue, lineWidth: 5) }
    }
}

struct HighlightMask: View {
    let app: String
    let title: String
    let windowID: Int
    @State var color: Color = .blue
    
    var body: some View {
        color
            .opacity(0.2)
            .cornerRadius(10)
            .help("\(app) - \(title)")
            .onPressGesture {
                if let mask = WindowHighlighter.shared.mask {
                    mask.order(.above, relativeTo: windowID)
                    if let window = getSCWindowWithID(UInt32(windowID)),
                       !SCManager.pinnedWdinwows.contains(window),
                       let display = getSCDisplayWithMouse() {
                        mask.close()
                        createNewWindow(display: display, window: window)
                        WindowHighlighter.shared.stopMouseMonitor()
                        return
                    }
                    color = .red
                    withAnimation(.easeInOut(duration: 0.6)) { color = .blue }
                }
            }
    }
}

class WindowHighlighter {
    static let shared = WindowHighlighter()
    var mouseMonitor: Any?
    var mouseMonitorL: Any?
    var targetWindowID: Int?
    var mask: EscPanel?
    
    func registerMouseMonitor() {
        closeMainWindow()
        DispatchQueue.main.async { tips("Click on the window you want to pin\nor press Esc to cancel.".local, id: "topit.how-to-select.note") }
        
        for screen in NSScreen.screens {
            let cover = EscPanel(contentRect: screen.frame, styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            cover.contentView = NSHostingView(rootView: CoverView())
            cover.level = .statusBar
            cover.sharingType = .none
            cover.backgroundColor = .clear
            cover.ignoresMouseEvents = true
            cover.isReleasedWhenClosed = false
            cover.collectionBehavior = [.canJoinAllSpaces, .stationary]
            cover.title = "TopitToo Screen Cover"
            cover.orderFront(self)
        }
        
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in self.updateMask() }
        }
        if mouseMonitorL == nil {
            mouseMonitorL = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
                self.updateMask()
                return event
            }
        }
    }
        
    func stopMouseMonitor() {
        // Remove monitors first (synchronous) to stop updateMask from creating new windows
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = mouseMonitorL {
            NSEvent.removeMonitor(monitor)
            mouseMonitorL = nil
        }
        // Close all auxiliary windows by title (catches orphaned masks from updateMask races)
        for w in NSApp.windows.filter({
            $0.title == "TopitToo Screen Cover" || $0.title == "TopitToo Mask Window"
        }) { w.close() }
        mask = nil
        targetWindowID = nil
    }
    
    func updateMask() {
        guard let targetWindow = getWindowUnderMouse() else {
            mask?.close()
            targetWindowID = nil
            return
        }
        
        if let app = targetWindow["kCGWindowOwnerName"] as? String, app != "TopitToo",
           let windowID = targetWindow["kCGWindowNumber"] as? Int, targetWindowID != windowID {
            mask?.close()
            targetWindowID = windowID
            createMaskWindow(window: targetWindow)
        }
    }
    
    func createMaskWindow(window: [String: Any]) {
        guard let windowID = targetWindowID, let frame = getCGWindowFrame(window: window) else { return }
        let app = window["kCGWindowOwnerName"] as? String ?? ""
        let title = window["kCGWindowName"] as? String ?? ""
        
        mask = EscPanel(contentRect: CGRectTransform(cgRect: frame),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        let contentView = NSHostingView(rootView: HighlightMask(app: app, title: title, windowID: windowID))
        mask?.contentView = contentView
        mask?.title = "TopitToo Mask Window"
        mask?.hasShadow = false
        mask?.sharingType = .none
        mask?.backgroundColor = .clear
        mask?.titleVisibility = .hidden
        mask?.isMovableByWindowBackground = false
        mask?.isReleasedWhenClosed = false
        mask?.collectionBehavior = [.canJoinAllSpaces, .transient]
        mask?.setFrame(CGRectTransform(cgRect: frame), display: true)
        mask?.order(.above, relativeTo: windowID)
        mask?.makeKey()
    }
}

extension View {
    func onPressGesture(perform: @escaping () -> Void) -> some View {
        self.gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                perform()
            }
        )
    }
}
