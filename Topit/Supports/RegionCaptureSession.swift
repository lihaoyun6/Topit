import AppKit
import CoreImage
import ScreenCaptureKit

/// A window-only stream: occluding windows and Topit's own panels never enter the image.
final class RegionCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private let region: CGRect
    private let queue = DispatchQueue(label: "com.lihaoyun6.Topit.region.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var stream: SCStream?
    private var stopped = false
    private var starting = false
    private var deliveryPending = false // Accessed only on queue; bound main-thread frame delivery.
    var onImage: ((CGImage) -> Void)?
    var onError: ((Error) -> Void)?

    init(region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
        self.region = region
    }

    @MainActor func start(window: SCWindow) async {
        guard !stopped, stream == nil else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale: CGFloat
        if #available(macOS 14, *) {
            scale = CGFloat(filter.pointPixelScale)
            configuration.ignoreShadowsSingleWindow = true
        } else {
            scale = NSScreen.screens.first(where: {
                $0.frame.intersects(CGRectTransform(cgRect: window.frame))
            })?.backingScaleFactor ?? 2
        }
        configuration.width = max(2, Int(window.frame.width * scale))
        configuration.height = max(2, Int(window.frame.height * scale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.queueDepth = 3
        let fps = min(max(ud.object(forKey: "maxFps") as? Int ?? 30, 1), 30)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        if #available(macOS 13, *) { configuration.capturesAudio = false }
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        stream = newStream
        starting = true
        defer { starting = false }
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await newStream.startCapture()
            // Closing while startCapture is suspended must not leave a stream running.
            if stopped {
                try? await newStream.stopCapture()
                stream = nil
            }
        } catch {
            stream = nil
            if !stopped { onError?(error) }
        }
    }

    // Lifecycle calls and callbacks are serialized on the main thread.
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopped = true
        onImage = nil
        onError = nil
        // start() owns cleanup until its asynchronous start completes.
        if starting { return }
        let oldStream = stream
        stream = nil
        Task { try? await oldStream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, !deliveryPending, let frame = render(sampleBuffer) else { return }
        deliveryPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.stopped { self.onImage?(frame) }
            self.queue.async { self.deliveryPending = false }
        }
    }

    // Kept separate so cropping can be verified with synthetic frames without screen permissions.
    func render(_ sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let status = info[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        var contentRect = image.extent
        if let value = info[.contentRect] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: value),
           let scale = info[.scaleFactor] as? CGFloat {
            contentRect = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                 width: rect.width * scale, height: rect.height * scale)
        }
        let crop = RegionGeometry.pixelCrop(region, contentRect: contentRect, pixelSize: image.extent.size)
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        return context.createCGImage(image, from: crop)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stream = nil
            self.onError?(error)
        }
    }
}
