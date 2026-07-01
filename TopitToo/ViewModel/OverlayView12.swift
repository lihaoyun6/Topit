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

struct OverlayView12: View {
    var display: SCDisplay!
    var window: SCWindow!
    @State private var timer: Timer?
    @StateObject private var cm = ScreenCaptureManager()
    @State private var opacity: Double = 1
    @State private var overButtons: Bool = false
    @State private var overView: Bool = false
    @State private var resizing: Bool = false
    @State private var nsWindow: NSWindow?
    @State private var nsScreen: NSScreen?
    @State private var axWindow: AXUIElement?
    @State private var windowSize: CGSize = .zero
    
    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showUnpinButton") private var showUnpinButton: Bool = true
    @AppStorage("mouseOverAction") private var mouseOverAction: Bool = true
    @AppStorage("keepFocus") private var keepFocus: Bool = true
    @AppStorage("miniButton") private var miniButton: Bool = true
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
                                    w.makeKeyAndOrderFront(self)
                                    checkMouseLocation()
                                    if SCManager.pinnedWdinwows.count > 1 && isMacOS12 {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            let alert = createAlert(title: "Sorry", message: "You can only pin one window on macOS Monterey.", button1: "OK")
                                            alert.beginSheetModal(for: w) { _ in w.close() }
                                        }
                                    }
                                }
                            },
                            onWindowClose: {
                                SCManager.pinnedWdinwows.removeAll(where: { $0 === window })
                                timer?.invalidate()
                                nsWindow = nil
                                cm.stopCapture()
                            }
                        )
                    )
                    .onTapGesture {
                        if !mouseOverAction {
                            if let id = window.owningApplication?.bundleIdentifier, let win = nsWindow {
                                activateWindow(axWindow: axWindow, frame: CGRectTransform(cgRect: win.frame))
                                NSApp.activate(ignoringOtherApps: true)
                                bringAppToFront(bundleIdentifier: id)
                                withAnimation(.easeOut(duration: 0.1)) { opacity = 0 }
                            }
                        }
                    }
            }.opacity(opacity)
            if !resizing {
                HStack {
                    if axWindow != nil && showCloseButton {
                        Button(action: {
                            nsWindow?.close()
                            _ = closeAXWindow(axWindow)
                        }, label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .frame(width: 12, height: 12)
                                .foregroundStyle(overButtons ? .buttonRedDark : .clear)
                                .background(Circle().fill(.buttonRed))
                        })
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                    if showUnpinButton {
                        Button(action: {
                            nsWindow?.close()
                        }, label: {
                            Image(systemName: "pin.slash.fill")
                                .font(.system(size: 7, weight: .black))
                                .frame(width: 12, height: 12)
                                .rotationEffect(.degrees(45))
                                .foregroundStyle(overButtons ? .buttonYellowDark : .clear)
                                .background(Circle().fill(.buttonYellow))
                        })
                        .buttonStyle(.plain)
                        .help("Unpin")
                    }
                }
                .focusable(false)
                .onHover { hovering in
                    overButtons = hovering
                    nsWindow?.makeKeyAndOrderFront(self)
                }
                .offset(x: closeButtonOffset.x, y: closeButtonOffset.y)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.blackWhite)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.secondary.opacity(0.5), lineWidth: 1)
                        .padding(0.5)
                }
                .padding(4)
            }
        }
        .onAppear {
            windowSize = window.frame.size
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let frame = getCGWindowFrameWithID(window.windowID) {
                    let newFrame = CGRectTransform(cgRect: frame)
                    if newFrame != nsWindow?.frame {
                        opacity = 0
                        resizing = true
                        let newDisplay = nsWindow?.screen
                        if newFrame.size != nsWindow?.frame.size || nsScreen != newDisplay {
                            nsScreen = newDisplay
                            cm.updateStreamSize(newWidth: frame.width, newHeight: frame.height, screen: newDisplay)
                        }
                        nsWindow?.setFrame(CGRectTransform(cgRect: frame), display: true)
                        windowSize = frame.size
                    } else {
                        if !overView { opacity = 1 }
                        resizing = false
                    }
                }
                checkMouseLocation()
            }
            axWindow = getAXWindow(windowID: window.windowID)
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
            Task { await cm.startCapture(display: display, window: window) }
        }
        .onChange(of: cm.capturing) { newValue in if !newValue { nsWindow?.close() }}
        .onChange(of: opacity) { newValue in
            if newValue == 1 { nsWindow?.hasShadow = true } else { nsWindow?.hasShadow = false }
        }
    }
    
    private func checkMouseLocation() {
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = nsWindow?.frame ?? CGRectTransform(cgRect: window.frame)
        let mouseInWindow = windowFrame.contains(NSPoint(x: mouseLocation.x, y: mouseLocation.y))
        if resizing { return }
        if mouseInWindow {
            if !keepFocus || mouseOverAction { nsWindow?.makeKeyAndOrderFront(self) }
            if overView == mouseInWindow || !mouseOverAction { return }
            if let id = window.owningApplication?.bundleIdentifier, let win = nsWindow {
                activateWindow(axWindow: axWindow, frame: CGRectTransform(cgRect: win.frame))
                NSApp.activate(ignoringOtherApps: true)
                bringAppToFront(bundleIdentifier: id)
                withAnimation(.easeOut(duration: 0.1)) { opacity = 0 }
            }
        } else {
            opacity = 1
        }
        overView = mouseInWindow
    }
}
