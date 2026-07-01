//
//  ScreenCaptureManager.swift
//  TopitToo
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
    static private let excludedApps = ["", "com.apple.dock", "com.apple.screencaptureui", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status", "com.macpaw.CleanMyMac4", "com.lihaoyun6.TopitToo"]
    
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
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        self.updateAvailableContent() {_ in}
                    }
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
    @Published var windowThumbnails = [SCDisplay:[WindowThumbnail]]()
    @Published var isReady = false
    private var allWindows = [SCWindow]()
    private var streams = [SCStream]()
    
    override init() {
        super.init()
        //DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.setupStreams(filter: filter) }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        let nsImage: NSImage
        if let cgImage = cgImage {
            nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            nsImage = NSImage.unknowScreen
        }
        if let index = streams.firstIndex(of: stream), index + 1 <= allWindows.count {
            let currentWindow = allWindows[index]
            let thumbnail = WindowThumbnail(image: nsImage, window: currentWindow)
            guard let displays = SCManager.availableContent?.displays.filter({ currentWindow.frame.intersects($0.frame) }) else {
                self.streams[index].stopCapture()
                return
            }
            for d in displays {
                DispatchQueue.main.async {[self] in
                    if windowThumbnails[d] != nil {
                        if !windowThumbnails[d]!.contains(where: { $0.window == currentWindow }) { windowThumbnails[d]!.append(thumbnail) }
                    } else {
                        windowThumbnails[d] = [thumbnail]
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { self.streams[index].stopCapture() }
            if index + 1 == streams.count { DispatchQueue.main.async { self.isReady = true }}
        }
    }

    func setupStreams(filter: Bool = false, capture: Bool = true) {
        SCManager.updateAvailableContent {[self] availableContent in
            Task {
                do {
                    streams.removeAll()
                    DispatchQueue.main.async { self.windowThumbnails.removeAll() }
                    allWindows = SCManager.getWindows().filter({
                        !($0.title == "" && $0.owningApplication?.bundleIdentifier == "com.apple.finder")
                        && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                        && $0.owningApplication?.applicationName != ""
                    })
                    if filter { allWindows = allWindows.filter({ $0.title != "" }) }
                    if capture {
                        let contentFilters = allWindows.map { SCContentFilter(desktopIndependentWindow: $0) }
                        for (index, contentFilter) in contentFilters.enumerated() {
                            let streamConfiguration = SCStreamConfiguration()
                            let width = allWindows[index].frame.width
                            let height = allWindows[index].frame.height
                            var factor = 0.5
                            if width < 200 && height < 200 { factor = 1.0 }
                            streamConfiguration.width = Int(width * factor)
                            streamConfiguration.height = Int(height * factor)
                            streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1))
                            streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
                            if #available(macOS 13, *) { streamConfiguration.capturesAudio = false }
                            streamConfiguration.showsCursor = false
                            streamConfiguration.scalesToFit = true
                            streamConfiguration.queueDepth = 3
                            let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)
                            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                            try await stream.startCapture()
                            streams.append(stream)
                        }
                    } else {
                        for w in allWindows {
                            let thumbnail = WindowThumbnail(image: NSImage.unknowScreen, window: w)
                            guard let displays = availableContent?.displays.filter({ w.frame.intersects($0.frame) }) else { break }
                            for d in displays {
                                DispatchQueue.main.async {[self] in
                                    if windowThumbnails[d] != nil {
                                        if !windowThumbnails[d]!.contains(where: { $0.window == w }) {
                                            windowThumbnails[d]!.append(thumbnail)
                                        }
                                    } else {
                                        windowThumbnails[d] = [thumbnail]
                                    }
                                }
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.isReady = true }
                    }
                } catch {
                    print("Get windowshot error：\(error)")
                }
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
