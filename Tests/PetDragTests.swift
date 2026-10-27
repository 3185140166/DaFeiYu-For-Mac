import Foundation
import CoreGraphics

@main struct PetDragTests {
    static func main() {
        let size = CGSize(width: 106, height: 120)
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080)] {
            for right in [false, true] {
                let edgeX = right ? screen.maxX - size.width : screen.minX
                for distance: CGFloat in [0, 5, 12, 13, 40] {
                    let origin = CGPoint(x: edgeX + (right ? -distance : distance), y: 100)
                    precondition(PetDragGeometry.shouldDetach(origin: origin, size: size, screen: screen, onRight: right) == (distance > 12))
                }
                let outward = CGPoint(x: edgeX + (right ? 20 : -20), y: 100)
                precondition(!PetDragGeometry.shouldDetach(origin: outward, size: size, screen: screen, onRight: right))
            }
        }
        let pointer = CGPoint(x: 250, y: 350)
        let origin = PetDragGeometry.floatingOrigin(pointer: pointer, proposedOrigin: CGPoint(x: 200, y: 300),
                                                    oldSize: CGSize(width: 100, height: 100), newSize: CGSize(width: 200, height: 300))
        precondition(origin == CGPoint(x: 150, y: 200))
        print("PASS: left/right detach threshold, negative screen coordinates, outward/vertical movement and resize grab anchor")
    }
}
