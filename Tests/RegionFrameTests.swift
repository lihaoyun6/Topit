import AppKit
import ScreenCaptureKit

@main
struct RegionFrameTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 200, 160, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        // BGRA: red in top-left, green in top-right, blue across the bottom.
        for y in 0..<160 {
            for x in 0..<200 {
                let offset = y * stride + x * 4
                base[offset] = y >= 80 ? 255 : 0
                base[offset + 1] = y < 80 && x >= 100 ? 255 : 0
                base[offset + 2] = y < 80 && x < 100 ? 255 : 0
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
                                                formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
        let frame = sample!
        let array = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: true)!
        let metadata = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: NSMutableDictionary.self)
        metadata[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.complete.rawValue
        metadata[SCStreamFrameInfo.scaleFactor.rawValue] = CGFloat(2)
        metadata[SCStreamFrameInfo.contentRect.rawValue] = CGRect(x: 0, y: 0, width: 100, height: 80).dictionaryRepresentation
        func rgb(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { data in
                let ctx = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return bytes
        }
        let red = RegionCaptureSession(region: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let redImage = red.render(frame)!
        check(redImage.width == 100 && redImage.height == 80, "retina dimensions")
        let redPixel = rgb(redImage)
        check(redPixel[0] > 250 && redPixel[1] < 5 && redPixel[2] < 5, "top-left contains only red")
        let green = RegionCaptureSession(region: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let greenPixel = rgb(green.render(frame)!)
        check(greenPixel[0] < 5 && greenPixel[1] > 250 && greenPixel[2] < 5, "top-right contains only green")
        let blue = RegionCaptureSession(region: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        let bluePixel = rgb(blue.render(frame)!)
        check(bluePixel[0] < 5 && bluePixel[1] < 5 && bluePixel[2] > 250, "bottom contains only blue")
        // Padding around the window must not change the normalized crop's origin.
        metadata[SCStreamFrameInfo.contentRect.rawValue] = CGRect(x: 10, y: 5, width: 80, height: 70).dictionaryRepresentation
        let padded = red.render(frame)!
        check(padded.width == 80 && padded.height == 70, "metadata excludes padding")
        let paddedPixel = rgb(padded)
        check(paddedPixel[0] > 250 && paddedPixel[1] < 5 && paddedPixel[2] < 5, "offset metadata selects correct pixels")
        metadata[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.idle.rawValue
        check(red.render(frame) == nil, "idle frames do not replace last image")
        metadata[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.blank.rawValue
        check(red.render(frame) == nil, "blank frames do not replace last image")
        red.stop()
        green.stop()
        blue.stop()
        print("Passed \(checks) frame rendering checks")
    }
}
