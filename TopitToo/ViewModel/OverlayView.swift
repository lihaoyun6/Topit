//
//  ScreenCaptureView.swift
//  TopitToo
//
//  Created by apple on 2024/11/23.
//


import SwiftUI
import Foundation
import AVFoundation
import ScreenCaptureKit

struct MenuItem<Content: View>: View {
    var destructive = false
    var action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            content()
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? (destructive ? .red : .blue) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover in hovering = hover}
        .foregroundStyle(hovering ? .white : (destructive ? .red : .primary))
        
    }
}

struct OverlayView: View {
    var display: SCDisplay!
    var window: SCWindow!
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
    
    @State private var capturing: Bool = false
    @State private var pausing: Bool = false
    
    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showUnpinButton") private var showUnpinButton: Bool = true
    @AppStorage("showPauseButton") private var showPauseButton: Bool = true
    @AppStorage("mouseOverAction") private var mouseOverAction: Bool = true
    @AppStorage("keepFocus") private var keepFocus: Bool = false
    @AppStorage("autoAvoid") private var autoAvoid: Bool = true
    @AppStorage("buttonPosition") private var buttonPosition: Int = 0
    @State private var closeButtonOffset: CGPoint = .zero
    
    var body: some View {
        ZStack(alignment: Alignment(
            horizontal: buttonPosition < 2 ? .leading : .trailing,
            vertical: buttonPosition % 2 == 0 ? .top : .bottom
        )) {
            Group {
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
                                SCManager.pinnedWdinwows.removeAll(where: { $0 === window })
                                if let w = nsWindow, am.activedFrame == w.frame {
                                    am.activedFrame = .zero
                                }
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
            }
            .opacity(opacity)
            .allowsHitTesting(opacity != 0)
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
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5).padding(0.5)
                        }
                    }
                    if showPopover {
                        VStack(alignment: .leading, spacing: 2) {
                            MenuItem(action: {
                                nsWindow?.close()
                            }) {
                                HStack(spacing: 6) {
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
                                HStack(spacing: 6) {
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
                                            if userOpacity == 1 { return }
                                            tips("This window is in translucent mode.\nPlease don't resize it in this mode!\nIf you need to do this, pause it first.", id: "topit.do-not-resize.note")
                                            nsWindow?.close()
                                            if let _ = SCManager.updateAvailableContentSync(),
                                               let scDisplay = getSCDisplayWithMouse(),
                                               let scWindow = SCManager.getWindows().first(where: { $0.windowID == window.windowID }) {
                                                createNewWindow(display: scDisplay, window: scWindow , opacity: userOpacity)
                                            }
                                        }
                                    }
                                    .scaleEffect(0.55)
                                    .frame(height: 22)
                                    .padding(.horizontal, -20)
                                }
                            }//.onHover { hover in setOpacity = hover }
                            if axWindow != nil {
                                Divider().padding(.horizontal, 5)
                                MenuItem(destructive: true, action: {
                                    nsWindow?.close()
                                    _ = closeAXWindow(axWindow)
                                }) {
                                    HStack(spacing: 6) {
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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                                .padding(0.5)
                        )
                        .padding(.vertical, -4)
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
                                .stroke(.secondary.opacity(0.5), lineWidth: 0.5).padding(0.5)
                        }
                    }
                }
                .padding(4)
                .offset(x: closeButtonOffset.x, y: closeButtonOffset.y)
                .focusable(false)
                .onHover { hovering in
                    overButtons = hovering
                    if !pausing { nsWindow?.makeKeyAndOrderFront(self) }
                }
            }
        }
        .onAppear {
            windowSize = window.frame.size
            axWindow = getAXWindow(windowID: window.windowID)
            if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID)
                if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID)
                    if axWindow == nil { axWindow = getAXWindow(windowID: window.windowID) }
                }
            }
            let mainScreenHeight = NSScreen.screens.first(where: { $0.isMainScreen })?.frame.height ?? 0
            if let pos = getCloseButtonLocalCenter(windowFrame: window.frame, mainScreenHeight: mainScreenHeight, axWindow: axWindow) {
                // Default button center at current position (padding 4 + button radius 10)
                let defaultCenterX: CGFloat = buttonPosition < 2 ? 14 : (window.frame.width - 14)
                let defaultCenterY: CGFloat = buttonPosition % 2 == 0 ? 14 : (window.frame.height - 14)
                closeButtonOffset = CGPoint(x: pos.x - defaultCenterX, y: pos.y - defaultCenterY)
                print("[Topit] Button offset calculated: (\(closeButtonOffset.x), \(closeButtonOffset.y)), defaultCenter: (\(defaultCenterX), \(defaultCenterY))")
            } else {
                // AX detection failed — use hardcoded fallback offset for standard macOS close button
                print("[Topit] AX close button detection failed, hasAxWindow=\(axWindow != nil)")
            }
            Task {
                await cm.startCapture(display: display, window: window)
                self.capturing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                    //let front = isFrontmostWindow(appID: window.owningApplication?.processID, windowID: window.windowID)
                    //if let shadow = nsWindow?.hasShadow { if !front && !shadow { nsWindow?.hasShadow = true }}
                    if let frame = getCGWindowFrameWithID(window.windowID) {
                        let newFrame = CGRectTransform(cgRect: frame)
                        if newFrame != nsWindow?.frame && !showPopover {
                            opacity = 0
                            resizing = true
                            showPopover = false
                            if capturing { stopCapture() }
                            let newDisplay = nsWindow?.screen
                            if newFrame.size != nsWindow?.frame.size || nsScreen != newDisplay {
                                nsScreen = newDisplay
                                cm.updateStreamSize(newWidth: frame.width, newHeight: frame.height, screen: newDisplay)
                            }
                            nsWindow?.setFrame(CGRectTransform(cgRect: frame), display: true)
                            windowSize = frame.size
                        } else {
                            if !pausing {
                                if opacity == 0 {
                                    let mouseLocation = NSEvent.mouseLocation
                                    let mouseInWindow = newFrame.contains(mouseLocation)
                                    if !mouseInWindow && !overButtons {
                                        opacity = 1
                                        restartCapture()
                                    }
                                } else if !overView {
                                    if !capturing { restartCapture() }
                                    opacity = 1
                                }
                            }
                            if pausing { nsWindow?.order(.above, relativeTo: Int(window.windowID)) }
                            resizing = false
                        }
                    } else {
                        if cm.capturing { nsWindow?.close() }
                    }
                }
            }
        }
        .onChange(of: am.activedFrame) { newValue in
            if !autoAvoid { return }
            if let w = nsWindow, newValue != .zero, newValue != w.frame {
                if newValue.intersects(w.frame) {
                    pausing = true
                    nsWindow?.level = .normal
                    nsWindow?.order(.above, relativeTo: Int(window.windowID))
                    return
                }
            }
            pausing = false
            nsWindow?.level = .floating
        }
        .onChange(of: showPopover) { newValue in if !newValue { setOpacity = false }}
        .onChange(of: cm.capturError) { newValue in if newValue { nsWindow?.close() }}
        .onChange(of: opacity) { newValue in
            //nsWindow?.hasShadow = false
            if newValue == 1 { nsWindow?.hasShadow = true } else { nsWindow?.hasShadow = false }
        }
        .onHover { hovering in
            overView = hovering
            if resizing || pausing { return }
            if hovering {
                if !keepFocus || mouseOverAction { nsWindow?.makeKeyAndOrderFront(self) }
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
        if mouseInWindow { opacity = 0 }
    }
}

struct ScreenCaptureView: NSViewRepresentable {
    @ObservedObject var manager: ScreenCaptureManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateLayer(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateLayer(for: nsView)
    }

    private func updateLayer(for view: NSView) {
        guard let layer = view.layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let videoLayer = manager.videoLayer
        videoLayer.frame = view.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.addSublayer(videoLayer)
    }
}
