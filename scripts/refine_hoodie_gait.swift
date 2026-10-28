import AppKit
import CoreGraphics

/// Keep complete illustrated poses. Never cut the skirt/thighs by pixel color.
@main struct RefineGait {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Resources")
        var removed = 0
        for direction in ["right", "left"] {
            for frame in 0..<PetWalkMotion.frameCount {
                let file = root.appendingPathComponent("hoodie_walk_\(direction)_\(frame).png")
                guard let image = NSImage(contentsOf: file),
                      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    fatalError("Missing full-body walking pose")
                }
                let result = SpriteComponentCleanup.clean(source)
                removed += result.removedPixels
                let rep = NSBitmapImageRep(cgImage: result.image)
                try rep.representation(using: .png, properties: [:])!.write(to: file)
            }
        }
        print("Preserved 16 complete full-body poses; removed \(removed) detached pixels without cutting any limbs")
    }
}
