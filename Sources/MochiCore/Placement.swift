import Foundation
import CoreGraphics

public enum Placement {
    /// Select the display nearest the pet, including displays with negative origins.
    /// Clamp the whole pet to its usable area, away from the Dock and menu bar.
    public static func clamp(origin: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint {
        guard !screens.isEmpty else { return origin }
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = screens.min { distance(center, to: $0) < distance(center, to: $1) }!
        return CGPoint(x: min(max(origin.x, screen.minX), max(screen.minX, screen.maxX - size.width)),
                       y: min(max(origin.y, screen.minY), max(screen.minY, screen.maxY - size.height)))
    }

    private static func distance(_ p: CGPoint, to r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
