import CoreGraphics
import Foundation

/// Gait is driven by travelled points, not timer frequency.
enum PetWalkMotion {
    static let frameCount = 24
    struct FootPose {
        let x: CGFloat
        let lift: CGFloat
        let planted: Bool
    }
    /// Contact -> stance -> toe-off -> lifted passing -> next contact.
    /// Each leg retains its identity for the entire cycle, including the wrap.
    static func footPose(phase: Double, far: Bool) -> FootPose {
        let offset = phase + (far ? 0.5 : 0)
        let p = offset - floor(offset)
        let span: CGFloat = 27.648
        if p < 0.6 {
            return FootPose(x: span * (1 - CGFloat(p / 0.6) * 2), lift: 0, planted: true)
        }
        let u = (p - 0.6) / 0.4
        return FootPose(x: -span * CGFloat(cos(.pi * u)),
                        lift: 15 * CGFloat(pow(sin(.pi * u), 2)), planted: false)
    }
    static func stride(height: CGFloat) -> CGFloat { max(24, height * 0.144) }
    static func frame(distance: CGFloat, height: CGFloat) -> Int {
        let cycle = max(0, distance) / stride(height: height)
        return Int(floor(cycle * CGFloat(frameCount))) % frameCount
    }
    static func speed(height: CGFloat) -> CGFloat { min(72, max(28, height * 0.12)) }
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
