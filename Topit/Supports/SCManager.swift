//
//  ScreenCaptureManager.swift
//  Topit
//
//  Created by apple on 2024/11/17.
//

import SwiftUI
import ScreenCaptureKit
import Darwin

enum CaptureFrameRate: Int, CaseIterable {
    case adaptive = 10
    case standard = 30
    case high = 60
    case ultra = 120
    case noLimit = 65535

    static func migrated(_ stored: Int) -> CaptureFrameRate {
        // A missing value now defaults to 30 Hz. Existing values remain valid,
        // including the historical 65535 sentinel for No Limit.
        CaptureFrameRate(rawValue: stored) ?? .standard
    }

    func frameInterval(displayMaximum: Int) -> CMTime? {
        guard self != .noLimit else { return nil }
        return CMTime(value: 1, timescale: CMTimeScale(min(rawValue, max(1, displayMaximum))))
    }
}

enum CaptureQuality: Int, CaseIterable {
    // Default cap lowered 2560 -> 1920: pins render smoother with far less
    // backing memory; Balanced/Native remain for users who want pixels.
    case conservative = 1920
    case balanced = 3840
    case native = 0

    func dimensions(pointWidth: CGFloat, pointHeight: CGFloat, scale: CGFloat) -> (width: Int, height: Int) {
        let nativeWidth = max(1, Int((pointWidth * scale).rounded()))
        let nativeHeight = max(1, Int((pointHeight * scale).rounded()))
        guard rawValue > 0, max(nativeWidth, nativeHeight) > rawValue else { return (nativeWidth, nativeHeight) }
        let factor = CGFloat(rawValue) / CGFloat(max(nativeWidth, nativeHeight))
        return (max(1, Int((CGFloat(nativeWidth) * factor).rounded())), max(1, Int((CGFloat(nativeHeight) * factor).rounded())))
    }
}

struct CaptureDiagnostics: Equatable {
    var activePins = 0
    var width = 0
    var height = 0
    var fps = 0
    var queueDepth = 3

    var rawFrameBytes: Int { width * height * 4 }
}

struct CapturePolicy {
    static let queueDepth = 3
    static let defaultQuality = CaptureQuality.conservative

    static func configuration(frameRate: CaptureFrameRate, quality: CaptureQuality,
                              pointSize: CGSize, scale: CGFloat, displayMaximum: Int) -> (width: Int, height: Int, interval: CMTime?) {
        let dimensions = quality.dimensions(pointWidth: pointSize.width, pointHeight: pointSize.height, scale: scale)
        return (dimensions.width, dimensions.height, frameRate.frameInterval(displayMaximum: displayMaximum))
    }
}

class AvoidManager: ObservableObject {
    static let shared = AvoidManager()
    @Published var activedFrame: CGRect = .zero
}

class ScreenCaptureManager: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    @AppStorage("maxFps") private var maxFps: Int = CaptureFrameRate.standard.rawValue
    @AppStorage("captureQuality") private var captureQuality: Int = CapturePolicy.defaultQuality.rawValue
    
    @Published var videoLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    @Published var capturError: Bool = false
    @Published var capturing: Bool = false
    @Published private(set) var diagnostics = CaptureDiagnostics()
    private var stream: SCStream?
    private var configuration: SCStreamConfiguration = SCStreamConfiguration()
    private var filter: SCContentFilter!
    private var scDisplay: SCDisplay!
    private var acceptingFrames = false
    private var stopping = false
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch outputType {
        case .screen:
            // Enqueue on the sample-handler queue: hopping to main retains the
            // IOSurface past its lifetime and drops valid frames across restarts.
            guard acceptingFrames, self.stream === stream else { return }
            videoLayer.enqueue(sampleBuffer)
        case .audio:
            break
        case .microphone:
            break
        @unknown default:
            assertionFailure("unknown stream type".local)
        }
    }
    
    func startCapture(display: SCDisplay, window: SCWindow) async {
        // A previous async stop may still be in flight; wait briefly instead of
        // dropping the start (dropped starts left pins black until a later tick).
        var spins = 0
        while stopping, spins < 20 {
            try? await Task.sleep(for: .milliseconds(50))
            spins += 1
        }
        if stream != nil || stopping { return }
        guard window.frame.width > 0, window.frame.height > 0 else {
            reportCaptureFailure("Cannot capture a window with an empty frame")
            return
        }
        do {
            scDisplay = display
            // SCContentFilter must exist before reading pointPixelScale. The
            // previous order dereferenced the IUO `filter` and trapped during
            // the first pin operation.
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = max(0.1, CGFloat(filter.pointPixelScale))
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            let frameRate = CaptureFrameRate.migrated(maxFps)
            let quality = CaptureQuality(rawValue: captureQuality) ?? CapturePolicy.defaultQuality
            let policy = CapturePolicy.configuration(frameRate: frameRate, quality: quality,
                pointSize: window.frame.size, scale: scale,
                displayMaximum: display.nsScreen?.maximumFramesPerSecond ?? 60)
            if let interval = policy.interval { configuration.minimumFrameInterval = interval }
            configuration.queueDepth = CapturePolicy.queueDepth
            configuration.showsCursor = false
            configuration.scalesToFit = true
            if #available (macOS 13, *) { configuration.capturesAudio = false }

            if #available(macOS 14, *) {
                configuration.width = policy.width
                configuration.height = policy.height
            } else {
                let pointPixelScaleOld = display.nsScreen?.backingScaleFactor ?? 2
                let dimensions = quality.dimensions(pointWidth: window.frame.width, pointHeight: window.frame.height, scale: pointPixelScaleOld)
            configuration.width = dimensions.width
            configuration.height = dimensions.height
            }
            guard configuration.width > 0, configuration.height > 0 else {
                reportCaptureFailure("ScreenCaptureKit rejected an empty capture configuration")
                return
            }
            diagnostics = CaptureDiagnostics(activePins: SCManager.pinnedWdinwows.count, width: configuration.width,
                height: configuration.height, fps: frameRate == .noLimit ? 0 : frameRate.rawValue,
                queueDepth: CapturePolicy.queueDepth)
            
            stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            
            try await stream?.startCapture()
            acceptingFrames = true
            DispatchQueue.main.async {
                self.capturing = true
                self.capturError = false
            }
        } catch {
            print("Start capture failed with error: \(error)")
            DispatchQueue.main.async {
                self.releaseCaptureResources()
                self.capturing = false
                self.capturError = true
            }
        }
    }

    private func reportCaptureFailure(_ message: String) {
        #if DEBUG
        print("Capture unavailable: \(message)")
        #endif
        DispatchQueue.main.async {
            self.releaseCaptureResources()
            self.capturError = true
        }
    }

    private func releaseCaptureResources(clearCaptureTarget: Bool = true) {
        autoreleasepool {
            acceptingFrames = false
            stream = nil
            if clearCaptureTarget {
                filter = nil
                scDisplay = nil
            }
            configuration = SCStreamConfiguration()
            diagnostics = CaptureDiagnostics()
            videoLayer.flushAndRemoveImage()
            videoLayer.removeFromSuperlayer()
            videoLayer = AVSampleBufferDisplayLayer()
            capturing = false
            CATransaction.flush()
        }
        // Return reclaimable allocator pages after the IOSurface/display-layer
        // references have been dropped. This is a best-effort relief call; it
        // does not fabricate a memory measurement or affect live allocations.
        _ = malloc_zone_pressure_relief(nil, 0)
    }
    
    func resumeCapture(newWidth: CGFloat, newHeight: CGFloat, screenID: CGDirectDisplayID? = nil) async {
        var spins = 0
        while stopping, spins < 20 {
            try? await Task.sleep(for: .milliseconds(50))
            spins += 1
        }
        if stopping { return }
        if stream != nil { return }
        guard filter != nil else {
            reportCaptureFailure("Cannot resume capture without an active content filter")
            return
        }
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
                self.releaseCaptureResources()
                self.capturError = true
            }
        }
    }
    
    func updateStreamSize(newWidth: CGFloat, newHeight: CGFloat, screen: NSScreen? = nil) {
        let pointPixelScaleOld = screen?.backingScaleFactor ?? 2
        let quality = CaptureQuality(rawValue: captureQuality) ?? CapturePolicy.defaultQuality
        let dimensions = quality.dimensions(pointWidth: newWidth, pointHeight: newHeight, scale: pointPixelScaleOld)
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.queueDepth = CapturePolicy.queueDepth
        configuration.scalesToFit = true
        
        let configuredFrameRate = CaptureFrameRate.migrated(maxFps)
        // Adaptive mode starts at 10 Hz and is promoted during resize/motion,
        // which is the existing high-frequency observation path.
        let frameRate = configuredFrameRate == .adaptive ? .high : configuredFrameRate
        if let interval = frameRate.frameInterval(displayMaximum: screen?.maximumFramesPerSecond ?? 60) {
            configuration.minimumFrameInterval = interval
        }
        diagnostics = CaptureDiagnostics(activePins: SCManager.pinnedWdinwows.count, width: dimensions.width,
            height: dimensions.height, fps: frameRate == .noLimit ? 0 : frameRate.rawValue, queueDepth: CapturePolicy.queueDepth)

        stream?.updateConfiguration(configuration) { error in
            if let error = error { print("Failed to update stream configuration: \(error)") }
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        #if DEBUG
        print("Capture stopped with error: \(error)")
        #endif
        DispatchQueue.main.async {
            self.releaseCaptureResources()
            self.capturError = true
        }
    }

    func stopCapture(preservingCaptureTarget: Bool = false) {
        guard !stopping else { return }
        stopping = true
        acceptingFrames = false
        let streamToStop = stream
        guard let streamToStop else {
            releaseCaptureResources()
            stopping = false
            return
        }
        try? streamToStop.removeStreamOutput(self, type: .screen)
        streamToStop.stopCapture { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async{
                self.releaseCaptureResources(clearCaptureTarget: !preservingCaptureTarget)
                self.stopping = false
                self.capturError = false
                if let error = error {
                    #if DEBUG
                    print("Failed to stop capture: \(error)")
                    #endif
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
    // Shared converter: one CIContext for all thumbnails instead of one per frame.
    private let thumbContext = CIContext(options: [.cacheIntermediates: false])
    // Throttle: focus/activate events must not re-capture (+20-50 MB a time).
    private var lastSetup = Date.distantPast
    private var teardownPending = false

    override init() {
        super.init()
        //DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.setupStreams(filter: filter) }
    }

    /// Stop every preview stream, drop outputs, purge thumbnails and return
    /// pages. Call when the selector closes; without this, closed selectors
    /// keep IOSurface queues + NSImages alive and memory never drops.
    func teardownPreviews() {
        teardownPending = true
        let oldStreams = streams
        streams.removeAll()
        allWindows.removeAll()
        Task {
            for old in oldStreams {
                try? old.removeStreamOutput(self, type: .screen)
                try? await stopPreviewStream(old)
            }
            DispatchQueue.main.async { [weak self] in
                self?.windowThumbnails.removeAll()
                self?.isReady = false
            }
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Decoded on the sample queue (background since setupStreams registers
        // .global): a fresh CIContext per frame on main caused focus/move spikes.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = thumbContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
            if index + 1 == streams.count { DispatchQueue.main.async { self.isReady = true }}
        }
    }

    func setupStreams(filter: Bool = false, capture: Bool = true, force: Bool = false) {
        // Coalesce focus/activate storms: a re-capture costs 20-50 MB and
        // spikes CPU to 30%+. At most one setup per 3 s unless forced.
        let now = Date()
        if !force {
            guard now.timeIntervalSince(lastSetup) > 3 else { return }
        }
        lastSetup = now
        teardownPending = false
        SCManager.updateAvailableContent {[self] availableContent in
            Task {
                do {
                    // Tear down previous preview streams before dropping them:
                    // orphaned SCStreams keep IOSurface queues alive and grow
                    // memory every time the selector opens or refreshes.
                    let oldStreams = streams
                    streams.removeAll()
                    for old in oldStreams {
                        try? old.removeStreamOutput(self, type: .screen)
                        try? await stopPreviewStream(old)
                    }
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
                            if teardownPending { break }
                            let streamConfiguration = SCStreamConfiguration()
                            // Thumbnails render at 160x90: capture at most 320px
                            // wide. The old 0.5x full-window capture decoded
                            // megabytes per window for a 160px image.
                            let w = allWindows[index].frame.width
                            let h = allWindows[index].frame.height
                            let longEdge = max(1, Int(max(w, h).rounded()))
                            let factor = min(1.0, 320.0 / CGFloat(longEdge))
                            streamConfiguration.width = max(1, Int((w * factor).rounded()))
                            streamConfiguration.height = max(1, Int((h * factor).rounded()))
                            streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1))
                            streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
                            if #available(macOS 13, *) { streamConfiguration.capturesAudio = false }
                            streamConfiguration.showsCursor = false
                            streamConfiguration.scalesToFit = true
                            streamConfiguration.queueDepth = 1
                            let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)
                            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                            try await stream.startCapture()
                            streams.append(stream)
                            // Preview capture is startup work, not a set of
                            // persistent pinned streams. Keep at most one
                            // preview stream alive at a time so opening the
                            // selector does not allocate N IOSurface queues.
                            try await Task.sleep(for: .milliseconds(150))
                            try await stopPreviewStream(stream)
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

    private func stopPreviewStream(_ stream: SCStream) async throws {
        try? stream.removeStreamOutput(self, type: .screen)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
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
