//
//  ScreenCaptureManager.swift
//  Topit
//
//  Created by apple on 2024/11/17.
//

import SwiftUI
import ScreenCaptureKit

class AvoidManager: ObservableObject {
    static let shared = AvoidManager()
    @Published var activedFrame: CGRect = .zero
}

class ScreenCaptureManager: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    @AppStorage("maxFps") private var maxFps: Int = 65535
    
    @Published var videoLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    @Published var capturError: Bool = false
    @Published var capturing: Bool = false
    private var stream: SCStream?
    private var configuration: SCStreamConfiguration = SCStreamConfiguration()
    private var filter: SCContentFilter!
    private var scDisplay: SCDisplay!
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch outputType {
        case .screen:
            DispatchQueue.main.async { [weak self] in
                self?.videoLayer.enqueue(sampleBuffer)
            }
        case .audio:
            break
        case .microphone:
            break
        @unknown default:
            assertionFailure("unknown stream type".local)
        }
    }
    
    func startCapture(display: SCDisplay, window: SCWindow) async {
        if stream != nil { return }
        do {
            scDisplay = display
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            let frameRate = min(maxFps, display.nsScreen?.maximumFramesPerSecond ?? 60)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            configuration.showsCursor = false
            if #available (macOS 13, *) { configuration.capturesAudio = false }

            filter = SCContentFilter(desktopIndependentWindow: window)
            if #available(macOS 14, *) {
                configuration.width = Int(filter.contentRect.width) * Int(filter.pointPixelScale)
                configuration.height = Int(filter.contentRect.height) * Int(filter.pointPixelScale)
            } else {
                let pointPixelScaleOld = display.nsScreen?.backingScaleFactor ?? 2
                configuration.width = Int(window.frame.width * pointPixelScaleOld)
                configuration.height = Int(window.frame.height * pointPixelScaleOld)
            }
            
            stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            
            try await stream?.startCapture()
            DispatchQueue.main.async {
                self.capturing = true
                self.capturError = false
            }
        } catch {
            print("Start capture failed with error: \(error)")
            DispatchQueue.main.async {
                self.stream = nil
                self.capturing = false
                self.capturError = true
            }
        }
    }
    
    func resumeCapture(newWidth: CGFloat, newHeight: CGFloat, screenID: CGDirectDisplayID? = nil) async {
        if stream != nil { return }
        let screen = NSScreen.screens.first(where: { $0.displayID == screenID })
        updateStreamSize(newWidth: newWidth, newHeight: newHeight, screen: screen)
        do {
            if stream != nil { return }
            stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try await stream?.startCapture()
            DispatchQueue.main.async {
                self.capturing = true
                self.capturError = false
            }
        } catch {
            print("Resume capture failed with error: \(error)")
            DispatchQueue.main.async {
                self.stream = nil
                self.capturing = false
                self.capturError = true
            }
        }
    }
    
    func updateStreamSize(newWidth: CGFloat, newHeight: CGFloat, screen: NSScreen? = nil) {
        let pointPixelScaleOld = screen?.backingScaleFactor ?? 2
        configuration.width = Int(newWidth * pointPixelScaleOld)
        configuration.height = Int(newHeight * pointPixelScaleOld)
        
        let frameRate = min(maxFps, screen?.maximumFramesPerSecond ?? 60)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        stream?.updateConfiguration(configuration) { error in
            if let error = error { print("Failed to update stream configuration: \(error)") }
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Capture stopped with error: \(error)")
        DispatchQueue.main.async {
            self.stream = nil
            self.capturing = false
            self.capturError = true
        }
    }

    func stopCapture() {
        if stream == nil { return }
        stream?.stopCapture { error in
            DispatchQueue.main.async{
                self.stream = nil
                self.capturing = false
                self.capturError = false
                self.videoLayer.removeFromSuperlayer()
                self.videoLayer = AVSampleBufferDisplayLayer()
                if let error = error {
                    print("Failed to stop capture: \(error)")
                    //self.capturError = true
                }
            }
        }
    }
}

class SCManager {
    static var pinnedWdinwows = [SCWindow]()
    static var availableContent: SCShareableContent?
    static private let excludedApps = ["", "com.apple.dock", "com.apple.screencaptureui", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status", "com.macpaw.CleanMyMac4", "com.lihaoyun6.Topit"]
    
    static func updateAvailableContentSync() -> SCShareableContent? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SCShareableContent? = nil

        updateAvailableContent { content in
            result = content
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
    
    static func updateAvailableContent(completion: @escaping (SCShareableContent?) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [self] content, error in
            if let error = error {
                switch error {
                case SCStreamError.userDeclined:
                    // The permission page provides an explicit retry; do not poll TCC.
                    break
                default:
                    print("Error: failed to fetch available content: ".local, error.localizedDescription)
                }
                completion(nil) // 在错误情况下返回 nil
                return
            }

            availableContent = content
            if let displays = content?.displays, !displays.isEmpty {
                completion(content) // 返回成功获取的 content
            } else {
                print("There needs to be at least one display connected!".local)
                completion(nil) // 如果没有显示器连接，则返回 nil
            }
        }
    }
    
    static func getWindows(noFilter: Bool = false) -> [SCWindow] {
        guard let content = availableContent else { return [] }
        var appBlackList = [String]()
        if let savedData = ud.data(forKey: "hiddenApps"),
           let decodedApps = try? JSONDecoder().decode([AppInfo].self, from: savedData) {
            appBlackList = (decodedApps as [AppInfo]).map({ $0.bundleID })
        }
        
        var windows = [SCWindow]()
        windows = content.windows.filter({
            guard let app = $0.owningApplication, let title = $0.title else { return false }
            return !excludedApps.contains(app.bundleIdentifier)
            && !appBlackList.contains(app.bundleIdentifier)
            && !title.contains("Item-0")
            && $0.frame.width > 40
            && $0.frame.height > 40
        })
        if !noFilter { windows = windows.filter({ !pinnedWdinwows.contains($0) }) }
        return windows
    }
}

class WindowSelectorViewModel: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    @Published var windowThumbnails = [SCDisplay: [WindowThumbnail]]()
    @Published var isReady = false
    private struct Request {
        let stream: SCStream
        let window: SCWindow
        let displays: [SCDisplay]
    }
    // Output callbacks and every mutation run on main. A refresh invalidates the
    // entire generation; callbacks never index arrays rebuilt by a newer refresh.
    private var generation = UUID()
    private var requests = [ObjectIdentifier: Request]()
    private var launching = false
    private let imageContext = CIContext()

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = requests.removeValue(forKey: ObjectIdentifier(stream)) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let thumbnail: NSImage
        if let cgImage = imageContext.createCGImage(image, from: image.extent) {
            thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            thumbnail = .unknowScreen
        }
        appendThumbnail(thumbnail, window: request.window, displays: request.displays)
        // Stop this exact stream, never an index into a later generation's array.
        stream.stopCapture(completionHandler: nil)
        if !launching && requests.isEmpty { isReady = true }
    }

    private func appendThumbnail(_ image: NSImage, window: SCWindow, displays: [SCDisplay]) {
        for display in displays {
            var items = windowThumbnails[display] ?? []
            if !items.contains(where: { $0.window.windowID == window.windowID }) {
                items.append(WindowThumbnail(image: image, window: window))
                windowThumbnails[display] = items
            }
        }
    }

    func setupStreams(filter: Bool = false, capture: Bool = true) {
        let current = UUID()
        generation = current
        launching = true
        isReady = false
        let previous = requests.values.map(\.stream)
        requests.removeAll()
        previous.forEach { $0.stopCapture(completionHandler: nil) }
        windowThumbnails.removeAll()
        SCManager.updateAvailableContent { [weak self] content in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                guard let content else { self.launching = false; self.isReady = true; return }
                let windows = SCManager.getWindows().filter {
                    !($0.title == "" && $0.owningApplication?.bundleIdentifier == "com.apple.finder")
                    && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                    && $0.owningApplication?.applicationName != ""
                    && (!filter || $0.title != "")
                }
                for window in windows {
                    guard self.generation == current else { return }
                    let displays = content.displays.filter { window.frame.intersects($0.frame) }
                    if !capture {
                        self.appendThumbnail(.unknowScreen, window: window, displays: displays)
                        continue
                    }
                    let config = SCStreamConfiguration()
                    let factor = window.frame.width < 200 && window.frame.height < 200 ? 1.0 : 0.5
                    config.width = max(1, Int(window.frame.width * factor))
                    config.height = max(1, Int(window.frame.height * factor))
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                    config.pixelFormat = kCVPixelFormatType_32BGRA
                    if #available(macOS 13, *) { config.capturesAudio = false }
                    config.showsCursor = false
                    config.scalesToFit = true
                    config.queueDepth = 3
                    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: self)
                    let key = ObjectIdentifier(stream)
                    self.requests[key] = Request(stream: stream, window: window, displays: displays)
                    do {
                        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                        try await stream.startCapture()
                    } catch {
                        if self.generation == current, self.requests.removeValue(forKey: key) != nil {
                            self.appendThumbnail(.unknowScreen, window: window, displays: displays)
                        }
                        stream.stopCapture(completionHandler: nil)
                    }
                    guard self.generation == current else { stream.stopCapture(completionHandler: nil); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak stream] in
                        guard let self, self.generation == current,
                              let pending = self.requests.removeValue(forKey: key) else { return }
                        self.appendThumbnail(.unknowScreen, window: pending.window, displays: pending.displays)
                        stream?.stopCapture(completionHandler: nil)
                        if !self.launching && self.requests.isEmpty { self.isReady = true }
                    }
                }
                self.launching = false
                if self.requests.isEmpty { self.isReady = true }
            }
        }
    }
}

class WindowThumbnail {
    let image: NSImage
    let window: SCWindow

    init(image: NSImage, window: SCWindow) {
        self.image = image
        self.window = window
    }
}
