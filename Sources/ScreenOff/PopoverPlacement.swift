import Foundation
import CoreGraphics

enum PopoverPlacement {
    /// AppKit coordinates are global screen points, including negative origins
    /// for displays placed above/left of the primary display. Keep AppKit's X
    /// placement (and therefore its arrow alignment), but pin the top edge to
    /// the status button when SwiftUI changes the popover's height.
    static func origin(frame: CGRect, anchor: CGRect, screen: CGRect) -> CGPoint {
        let gap: CGFloat = 2
        let top = min(anchor.minY - gap, screen.maxY - gap)
        let y = max(screen.minY, top - frame.height)
        let x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width))
        return CGPoint(x: x, y: y)
    }
}
