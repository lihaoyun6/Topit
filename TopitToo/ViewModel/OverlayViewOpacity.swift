//
//  OverlayViewOpacity.swift
//  TopitToo
//
//  Created by apple on 2024/11/29.
//


import SwiftUI
import Foundation
import AVFoundation
import ScreenCaptureKit

struct OverlayViewOpacity: View {
    var display: SCDisplay!
    var window: SCWindow!
    var Opacity: Double!
    @State private var timer: Timer?
    @StateObject private var cm = ScreenCaptureManager()
    @StateObject private var am = AvoidManager.shared
    @State private var opacity: Double = 1
    @State private var userOpacity: Double = 1
    @State private var setOpacity: Bool = false
    @State private var overButtons: Bool = false
    @State private var overView: Bool = false
    @State private var resizing: Bool = false
    @State private var showPopover: Bool = false
    @State private var nsWindow: NSWindow?
    @State private var nsScreen: NSScreen?
    @State private var axWindow: AXUIElement?
    @State private var windowSize: CGSize = .zero
    @State private var originoFrame: CGRect?
    
    @State private var capturing: Bool = false
    @State private var pausing: Bool = false
    
    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showUnpinButton") private var showUnpinButton: Bool = true
    @AppStorage("showPauseButton") private var showPauseButton: Bool = true
    @AppStorage("mouseOverAction") private var mouseOverAction: Bool = true
    @AppStorage("keepFocus") private var keepFocus: Bool = false
    @AppStorage("showBorder") private var showBorder: Bool = false
    @AppStorage("buttonPosition") private var buttonPosition: Int = 0
    @State private var closeButtonOffset: CGPoint = .zero
    
    var body: some View {
        ZStack(alignment: Alignment(
            horizontal: buttonPosition < 2 ? .leading : .trailing,
            vertical: buttonPosition % 2 == 0 ? .top : .bottom
        )) {
            ZStack {
                ScreenCaptureView(manager: cm)
                    .frame(width: windowSize.width, height: windowSize.height)
                    .background(
                        WindowAccessor(
                            onWindowOpen: { w in
                                nsWindow = w
                                SCManager.pinnedWdinwows.append(window)
                                if let w = nsWindow {
                                    nsScreen = w.screen
                                    w.makeKeyAndOrderFront(self)
                                    checkMouseLocation()
                                }
                            },
                            onWindowClose: {
                                if let window = nsWindow {
                                    activateWindow(axWindow: axWindow, frame: CGRectTransform(cgRect: window.frame))
                                }
                                SCManager.pinnedWdinwows.removeAll(where: { $0 === window })
                                timer?.invalidate()
                                nsWindow = nil
                                stopCapture()
                            }
                        )
                    )
                    .onTapGesture {
                        if !mouseOverAction {
                            nsWindow?.makeKeyAndOrderFront(self)
                            if activate() {
                                am.activedFrame = nsWindow?.frame ?? .zero
                                withAnimation(.easeOut(duration: 0.1)) { opacity = 0 }
                            }
                            stopCapture()
                        }
                    }
                    .opacity(opacity * userOpacity)
                if showBorder {
                    Rectangle()
                        .stroke(.buttonBlue, lineWidth: 2)
                        .padding(1)
                        .opacity(opacity * 0.8)
                }
            }
            if !resizing {
                VStack(alignment: buttonPosition < 2 ? .leading : .trailing) {
                    if buttonPosition % 2 == 0 {
                        Button(action: {
                            showPopover.toggle()
                        }, label: {
                            Image("statusIcon")
                                .resizable().scaledToFit()
                                .frame(width: 12, height: 12)
                                .padding(4)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.buttonBlue)
                                )
                        })
                        .buttonStyle(.plain)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                                .padding(0.5)
                        }
                    }
                    if showPopover {
                        VStack(spacing: 4) {
                            MenuItem(action: {
                                nsWindow?.close()
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "pin.circle")
                                    Text("Unpin").padding(.trailing, -11)
                                    Spacer()
                                }
                            }
                            Divider().padding(.horizontal, 5)
                            MenuItem(action: {
                                showPopover.toggle()
                                _ = activate()
                                pausing.toggle()
                                if pausing {
                                    nsWindow?.level = .normal
                                    nsWindow?.order(.above, relativeTo: Int(window.windowID))
                                    stopCapture()
                                } else {
                                    restartCapture()
                                    nsWindow?.level = .floating
                                }
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: pausing ? "play.circle" : "pause.circle")
                                    Text(pausing ? "Resume" : "Pause").padding(.trailing, -11)
                                    Spacer()
                                }
                            }
                            Divider().padding(.horizontal, 5)
                            ZStack {
                                if !setOpacity {
                                    MenuItem(action: {
                                        setOpacity = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "circle.righthalf.filled")
                                            Text("Opacity").padding(.trailing, -11)
                                            Spacer()
                                        }
                                    }
                                } else {
                                    Slider(value: $userOpacity, in: 0.2...1) { editing in
                                        if !editing {
                                            if userOpacity == 1 {
                                                nsWindow?.close()
                                                if let _ = SCManager.updateAvailableContentSync(),
                                                   let scDisplay = getSCDisplayWithMouse(),
                                                   let scWindow = SCManager.getWindows().first(where: { $0.windowID == window.windowID }) {
                                                    createNewWindow(display: scDisplay, window: scWindow)
                                                }
                                            }
                                        }
                                    }
                                    .scaleEffect(0.55)
                                    .frame(height: 22)
                                    .padding(.horizontal, -25)
                                }
                            }//.onHover { hover in setOpacity = hover  }
                            if axWindow != nil {
                                Divider().padding(.horizontal, 5)
                                MenuItem(destructive: true, action: {
                                    _ = activate()
                                    nsWindow?.close()
                                    _ = closeAXWindow(axWindow)
                                }) {
                                    HStack(spacing: 7) {
                                        Image(systemName: "xmark.circle")
                                        Text("Close").padding(.trailing, -11)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(5)
                        .fixedSize()
                        .background(BlurView(material: .menu))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.8, style: .continuous)
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                                .padding(0.5)
                        )
                        .padding(.top, -4)
                        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.2) ,radius: 3, y: 2)
                    }
                    if buttonPosition % 2 != 0 {
                        Button(action: {
                            showPopover.toggle()
                        }, label: {
                            Image("statusIcon")
                                .resizable().scaledToFit()
                                .frame(width: 12, height: 12)
                                .padding(4)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.buttonBlue)
                                )
                        })
                        .buttonStyle(.plain)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                                .padding(0.5)
                        }
                    }
                }
                .padding(4)
                .offset(x: closeButtonOffset.x, y: closeButtonOffset.y)
                .onHover { hovering in
                    overButtons = hovering
                    if !pausing { nsWindow?.makeKeyAndOrderFront(self) }
                }
            }
        }
        .onAppear {
            userOpacity = Opacity
            windowSize = window.frame.size
            axWindow = getAXWindow(windowID: window.windowID)
            if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID)
                if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID)
                    if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID) }
                }
            }
            let mainScreenHeight = NSScreen.screens.first(where: { $0.isMainScreen })?.frame.height ?? 0
            if let pos = getCloseButtonLocalCenter(windowFrame: window.frame, mainScreenHeight: mainScreenHeight, axWindow: axWindow) {
                let defaultCenterX: CGFloat = buttonPosition < 2 ? 14 : (window.frame.width - 14)
                let defaultCenterY: CGFloat = buttonPosition % 2 == 0 ? 14 : (window.frame.height - 14)
                closeButtonOffset = CGPoint(x: pos.x - defaultCenterX, y: pos.y - defaultCenterY)
                print("[Topit] Button offset calculated: (\(closeButtonOffset.x), \(closeButtonOffset.y)), defaultCenter: (\(defaultCenterX), \(defaultCenterY))")
            } else {
                // AX detection failed — use hardcoded fallback offset for standard macOS close button
                print("[Topit] AX close button detection failed, hasAxWindow=\(axWindow != nil)")
            }
            hideWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
                    //let front = isFrontmostWindow(appID: window.owningApplication?.processID, windowID: window.windowID)
                    //if let shadow = nsWindow?.hasShadow { if !front && !shadow { nsWindow?.hasShadow = true }}
                    if let frame = getCGWindowFrameWithID(window.windowID) {
                        let newFrame = CGRectTransform(cgRect: frame)
                        if newFrame != nsWindow?.frame && newFrame != originoFrame && !showPopover {
                            if !overView { return }
                            //resizing = true
                            opacity = 0
                            showPopover = false
                            let newDisplay = nsWindow?.screen
                            if newFrame.size != nsWindow?.frame.size || nsScreen != newDisplay {
                                nsScreen = newDisplay
                                cm.updateStreamSize(newWidth: frame.width, newHeight: frame.height, screen: newDisplay)
                            }
                            nsWindow?.setFrame(CGRectTransform(cgRect: frame), display: true)
                            windowSize = frame.size
                        } else {
                            if !overView && !pausing {
                                if !capturing { restartCapture() }
                                opacity = 1
                            }
                            if pausing { nsWindow?.order(.above, relativeTo: Int(window.windowID)) }
                            //resizing = false
                        }
                    } else {
                        if cm.capturing { nsWindow?.close() }
                    }
                }
            }
            Task {
                await cm.startCapture(display: display, window: window)
                self.capturing = true
            }
        }
        .onChange(of: showPopover) { newValue in if !newValue { setOpacity = false }}
        .onChange(of: cm.capturError) { newValue in if newValue { nsWindow?.close() }}
        //.onChange(of: opacity) { newValue in if newValue == 1 { nsWindow?.hasShadow = true } else { nsWindow?.hasShadow = false }}
        .onHover { hovering in
            overView = hovering
            if resizing || pausing { return }
            if !keepFocus || mouseOverAction { nsWindow?.makeKeyAndOrderFront(self) }
            if hovering {
                if !mouseOverAction { return }
                if activate() {
                    am.activedFrame = nsWindow?.frame ?? .zero
                    withAnimation(.easeOut(duration: 0.1)) { opacity = 0 }
                }
                stopCapture()
            } else {
                am.activedFrame = .zero
                showPopover = false
                restartCapture()
                opacity = 1
                hideWindow()
            }
        }
    }
    
    private func hideWindow() {
        moveAxWindow(axWindow: axWindow, origin: CGPoint(x: -65535, y: 65535))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let oFrame = getCGWindowFrameWithID(window.windowID) {
                originoFrame = CGRectTransform(cgRect: oFrame)
            }
        }
    }
    
    private func activate() -> Bool {
        if let id = window.owningApplication?.bundleIdentifier, let win = nsWindow {
            activateWindow(axWindow: axWindow, frame: CGRectTransform(cgRect: win.frame))
            NSApp.activate(ignoringOtherApps: true)
            bringAppToFront(bundleIdentifier: id)
            return true
        }
        return false
    }
    
    private func restartCapture() {
        if let frame = nsWindow?.frame {
            Task {
                await cm.resumeCapture(newWidth: frame.width, newHeight: frame.height, screenID: nsScreen?.displayID)
                self.capturing = true
            }
        }
    }
    
    private func stopCapture() {
        if !capturing { return }
        capturing = false
        cm.stopCapture()
    }
    
    private func checkMouseLocation() {
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = CGRectTransform(cgRect: window.frame)
        let mouseInWindow = windowFrame.contains(NSPoint(x: mouseLocation.x, y: mouseLocation.y))
        if mouseInWindow {
            opacity = 0
            _ = activate()
        }
    }
}
