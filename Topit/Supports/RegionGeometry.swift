import Foundation
import CoreGraphics

/// All selections use a top-left origin, normalized to the source window.
enum RegionGeometry {
    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }

    static func normalized(_ rect: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let clipped = rect.intersection(CGRect(origin: .zero, size: size))
        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else { return nil }
        return CGRect(x: clipped.minX / size.width, y: clipped.minY / size.height,
                      width: clipped.width / size.width, height: clipped.height / size.height)
    }

    /// Convert ScreenCaptureKit's top-left content bounds into Core Image's bottom-left pixels.
    static func pixelCrop(_ region: CGRect, contentRect: CGRect, pixelSize: CGSize) -> CGRect {
        let topLeft = CGRect(x: contentRect.minX + region.minX * contentRect.width,
                             y: contentRect.minY + region.minY * contentRect.height,
                             width: region.width * contentRect.width,
                             height: region.height * contentRect.height)
        // Round inward so no pixel outside the chosen region is displayed.
        let left = ceil(topLeft.minX)
        let right = floor(topLeft.maxX)
        let top = ceil(topLeft.minY)
        let bottom = floor(topLeft.maxY)
        return CGRect(x: left, y: pixelSize.height - bottom,
                      width: max(0, right - left), height: max(0, bottom - top))
            .intersection(CGRect(origin: .zero, size: pixelSize))
    }

    static func sourcePoint(_ point: CGPoint, viewSize: CGSize, region: CGRect, sourceFrame: CGRect) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0, sourceFrame.width > 0, sourceFrame.height > 0 else { return nil }
        // Clamp a drag leaving the panel to the selected content; never hit an outside control.
        let x = min(max(point.x / viewSize.width, 0), 1.nextDown)
        let y = min(max(point.y / viewSize.height, 0), 1.nextDown)
        return CGPoint(x: sourceFrame.minX + (region.minX + x * region.width) * sourceFrame.width,
                       y: sourceFrame.minY + (region.minY + y * region.height) * sourceFrame.height)
    }

}
