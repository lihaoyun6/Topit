import Foundation
import CoreGraphics

@main
struct RegionGeometryTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selected = RegionGeometry.selection(from: CGPoint(x: 600, y: 450),
                                                to: CGPoint(x: 200, y: 150), in: bounds)
        check(selected == CGRect(x: 200, y: 150, width: 400, height: 300), "reverse drag")
        check(RegionGeometry.selection(from: CGPoint(x: 700, y: 500), to: CGPoint(x: 1000, y: 900), in: bounds)
              == CGRect(x: 700, y: 500, width: 100, height: 100), "clamp to window")
        let normalized = RegionGeometry.normalized(selected, in: bounds.size)!
        check(normalized == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), "normalize")
        check(RegionGeometry.normalized(CGRect(x: 0, y: 0, width: 7, height: 40), in: bounds.size) == nil, "reject tiny selection")
        check(RegionGeometry.normalized(.zero, in: bounds.size) == nil, "click does not pin")
        check(RegionGeometry.normalized(selected, in: .zero) == nil, "reject empty window")
        check(RegionGeometry.normalized(CGRect(x: 900, y: 700, width: 30, height: 30), in: bounds.size) == nil, "reject disjoint selection")
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        check(RegionGeometry.pixelCrop(full, contentRect: CGRect(x: 0, y: 0, width: 1600, height: 1200), pixelSize: CGSize(width: 1600, height: 1200))
              == CGRect(x: 0, y: 0, width: 1600, height: 1200), "full retina frame")
        check(RegionGeometry.pixelCrop(CGRect(x: 0, y: 0, width: 0.5, height: 0.25), contentRect: CGRect(x: 0, y: 0, width: 1600, height: 1200), pixelSize: CGSize(width: 1600, height: 1200))
              == CGRect(x: 0, y: 900, width: 800, height: 300), "top-left to bottom-left conversion")
        check(RegionGeometry.pixelCrop(CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25), contentRect: CGRect(x: 0, y: 0, width: 1600, height: 1200), pixelSize: CGSize(width: 1600, height: 1200))
              == CGRect(x: 800, y: 0, width: 800, height: 300), "bottom-right conversion")
        check(RegionGeometry.pixelCrop(full, contentRect: CGRect(x: 20, y: 40, width: 800, height: 600), pixelSize: CGSize(width: 900, height: 700))
              == CGRect(x: 20, y: 60, width: 800, height: 600), "exclude shadow padding")
        check(RegionGeometry.pixelCrop(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), contentRect: CGRect(x: 0, y: 0, width: 99, height: 99), pixelSize: CGSize(width: 99, height: 99))
              == CGRect(x: 10, y: 40, width: 49, height: 49), "round inward to prevent outside pixels")
        check(RegionGeometry.pixelCrop(full, contentRect: CGRect(x: -10, y: -10, width: 120, height: 120), pixelSize: CGSize(width: 100, height: 100))
              == CGRect(x: 0, y: 0, width: 100, height: 100), "clamp metadata to image")
        let source = CGRect(x: -800, y: 100, width: 800, height: 600)
        let crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        check(RegionGeometry.sourcePoint(CGPoint(x: 100, y: 75), viewSize: CGSize(width: 200, height: 150), region: crop, sourceFrame: source)
              == CGPoint(x: -400, y: 400), "scaled input on a display left of main")
        check(RegionGeometry.sourcePoint(.zero, viewSize: CGSize(width: 200, height: 150), region: crop, sourceFrame: source)
              == CGPoint(x: -600, y: 250), "top-left input matches crop origin")
        check(RegionGeometry.sourcePoint(CGPoint(x: -100, y: -100), viewSize: CGSize(width: 200, height: 150), region: crop, sourceFrame: source)
              == CGPoint(x: -600, y: 250), "drag outside top-left remains inside crop")
        let edge = RegionGeometry.sourcePoint(CGPoint(x: 400, y: 400), viewSize: CGSize(width: 200, height: 150), region: crop, sourceFrame: source)!
        check(edge.x <= -200 && edge.y <= 550 && edge.x > -201 && edge.y > 549, "drag outside bottom-right remains inside crop")
        check(RegionGeometry.sourcePoint(.zero, viewSize: .zero, region: crop, sourceFrame: source) == nil, "zero-size view cannot inject input")
        print("Passed \(checks) region geometry checks")
    }
}
