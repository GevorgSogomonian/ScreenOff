import Foundation
import CoreGraphics

@main
enum PopoverPlacementTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            count += 1
            precondition(condition, message)
        }
        // Changing content height must leave the top edge beside the icon.
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let button = CGRect(x: 1400, y: 1056, width: 24, height: 24)
        for height in [251.0, 340.0, 251.0, 285.0] {
            let frame = CGRect(x: 1212, y: 700, width: 400, height: height)
            let result = PopoverPlacement.origin(frame: frame, anchor: button, screen: screen)
            check(result.y + height == button.minY - 2, "Top must stay anchored through growth and shrink")
            check(result.x == frame.minX, "Keep native horizontal/arrow alignment")
        }
        // Non-primary monitor coordinates must never be flipped, scaled, or
        // derived from NSScreen.main. Test monitors on all sides of the primary.
        for origin in [CGPoint(x: -1920, y: 0), CGPoint(x: 1920, y: -200),
                       CGPoint(x: 0, y: 1080), CGPoint(x: 0, y: -1200)] {
            let display = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
            let anchor = CGRect(x: origin.x + 1400, y: display.maxY - 24, width: 24, height: 24)
            let frame = CGRect(x: origin.x + 1212, y: origin.y + 500, width: 400, height: 251)
            let point = PopoverPlacement.origin(frame: frame, anchor: anchor, screen: display)
            check(point.y + frame.height == anchor.minY - 2, "Secondary screen vertical coordinates")
            check(display.contains(CGRect(origin: point, size: frame.size)), "Menu stays on the status button's display")
        }
        for x in [-100.0, 1850.0] {
            let frame = CGRect(x: x, y: 700, width: 400, height: 251)
            let point = PopoverPlacement.origin(frame: frame, anchor: button, screen: screen)
            check(screen.contains(CGRect(origin: point, size: frame.size)), "Clamp at display edges")
        }
        let smallScreen = CGRect(x: 0, y: 0, width: 800, height: 400)
        let tall = CGRect(x: 0, y: 0, width: 374, height: 390)
        let point = PopoverPlacement.origin(frame: tall, anchor: CGRect(x: 50, y: 376, width: 24, height: 24), screen: smallScreen)
        check(point.y == 0, "Never put the window below the visible display")
        print("PASS: \(count) popover positioning checks")
    }
}
