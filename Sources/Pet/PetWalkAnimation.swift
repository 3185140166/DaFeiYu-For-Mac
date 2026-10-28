import CoreGraphics
import Foundation

/// Gait is driven by travelled points, not timer frequency.
enum PetWalkMotion {
    static let frameCount = 8
    static func stride(height: CGFloat) -> CGFloat { max(24, height * 0.24) }
    static func frame(distance: CGFloat, height: CGFloat) -> Int {
        let cycle = max(0, distance) / stride(height: height)
        return Int(floor(cycle * CGFloat(frameCount))) % frameCount
    }
    static func speed(height: CGFloat) -> CGFloat { min(72, max(28, height * 0.20)) }
    static func cycleDuration(height: CGFloat) -> CFTimeInterval { Double(stride(height: height) / speed(height: height)) }
    static func step(remaining: CGFloat, height: CGFloat, elapsed: CFTimeInterval) -> CGFloat {
        let speed = speed(height: height)
        let distance = min(abs(remaining), speed * CGFloat(min(0.05, max(0, elapsed))))
        return remaining < 0 ? -distance : distance
    }
}

/// Stable resource names for the separately illustrated direction-specific cycle.
enum PetWalkRenderer {
    static func resourceName(frame: Int, facingLeft: Bool) -> String {
        let index = ((frame % PetWalkMotion.frameCount) + PetWalkMotion.frameCount) % PetWalkMotion.frameCount
        return "hoodie_walk_\(facingLeft ? "left" : "right")_\(index)"
    }
}
