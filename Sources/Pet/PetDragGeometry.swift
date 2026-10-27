import Foundation
import CoreGraphics

/// Edge distance is measured in points, independent of screen resolution.
enum PetDragGeometry {
    static let detachDistance: CGFloat = 12

    static func shouldDetach(origin: CGPoint, size: CGSize, screen: CGRect, onRight: Bool) -> Bool {
        let inwardDistance = onRight ? screen.maxX - (origin.x + size.width) : origin.x - screen.minX
        return inwardDistance > detachDistance
    }

    /// Keep the same relative grab point under the pointer when the artwork grows.
    static func floatingOrigin(pointer: CGPoint, proposedOrigin: CGPoint, oldSize: CGSize, newSize: CGSize) -> CGPoint {
        let x = min(max((pointer.x - proposedOrigin.x) / max(1, oldSize.width), 0), 1)
        let y = min(max((pointer.y - proposedOrigin.y) / max(1, oldSize.height), 0), 1)
        return CGPoint(x: pointer.x - x * newSize.width, y: pointer.y - y * newSize.height)
    }
}
