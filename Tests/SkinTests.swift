import AppKit
import CoreGraphics
import ImageIO

enum L10nKey { case skinBasin, skinMaid, skinHoodie }
extension Bundle {
    static var module: Bundle { Bundle(path: CommandLine.arguments[1])! }
}

@main struct SkinTests {
    @MainActor static func main() throws {
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        let hoodie = PetSkin.skin(at: PetSkin.defaultSkinIndex)
        check(hoodie.prefix == "hoodie" && hoodie.expressionCount == 1, "Wrong default or expression count")
        check(hoodie.resourceName(for: 0) == "hoodie_stand" && hoodie.resourceName(for: 1) == "hoodie_face_happy", "Wrong artwork mapping")
        check(hoodie.resourceName(for: 99) == hoodie.standResource, "Unsafe expression index")
        for skin in PetSkin.skins {
            check(PetArtworkStore.shared.sourceImage(skin: skin, expression: 0) != nil, "Missing standing art")
            check(PetArtworkStore.shared.availableExpressionCount(skin: skin) == skin.expressionCount, "Missing expression")
        }
        let idle = PetArtworkStore.shared.sourceImage(skin: hoodie, expression: 0)!
        let happy = PetArtworkStore.shared.sourceImage(skin: hoodie, expression: 1)!
        check(idle.width == happy.width && idle.height == happy.height && idle.width == 896 && idle.height == 640, "Mismatched canvas")
        let bitmap = PetBitmap(source: idle, pixelWidth: 896, pixelHeight: 640)!
        check(bitmap.alpha(x: 0, y: 0) == 0 && bitmap.alpha(x: 639, y: 639) == 0, "Opaque image corners")
        let view = PetView(frame: .zero)
        view.artworkSource = { skin, expression in PetArtworkStore.shared.sourceImage(skin: skin, expression: expression) }
        view.skinIndex = hoodie.index
        check(view.cycleExpression() == 1 && view.cycleExpression() == 0, "Hoodie does not toggle idle/happy")
        view.mode = .perch
        let expected = (hoodie.headX1 - hoodie.headX0) * CGFloat(idle.width) / ((hoodie.headY1 - hoodie.headY0) * CGFloat(idle.height))
        check(abs(view.perchHeadAspect - expected) < 0.0001, "Rotated head aspect is stretched")
        let perched = PetArtworkStore.shared.perchArtwork(skin: hoodie, expression: 0, pixelWidth: 192, aspect: view.perchHeadAspect)!
        let rep = NSBitmapImageRep(cgImage: perched.image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/hoodie-perch-preview.png"))
        check(Bundle.module.url(forResource: "HoodieArtworkLicense", withExtension: "txt") != nil, "Missing bundled license")
        check(abs(PetWalkMotion.cycleDuration(height: 240) - 1.2) < 0.001, "Gait still too fast")
        let cleanupContext = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cleanupContext.setFillColor(NSColor.blue.cgColor)
        cleanupContext.fill(CGRect(x: 30, y: 10, width: 35, height: 40))
        cleanupContext.fill(CGRect(x: 3, y: 20, width: 2, height: 14))
        let cleaned = SpriteComponentCleanup.clean(cleanupContext.makeImage()!)
        let cleanedBitmap = PetBitmap(source: cleaned.image, pixelWidth: 80, pixelHeight: 60)!
        check(cleaned.removedPixels >= 28 && cleanedBitmap.alpha(x: 3, y: 30) == 0 && cleanedBitmap.alpha(x: 45, y: 30) > 240, "Detached tile fragment was not removed")
        let rightFrames = PetArtworkStore.shared.walkFrames(skin: hoodie, facingLeft: false)
        let leftFrames = PetArtworkStore.shared.walkFrames(skin: hoodie, facingLeft: true)
        check(rightFrames.count == 8 && leftFrames.count == 8, "Missing walk directions or frames")
        func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }
        check(Set(rightFrames.map(png)).count == 8, "Gait frames do not advance through distinct leg poses")
        for frame in rightFrames + leftFrames {
            check(frame.width == 896 && frame.height == 640, "Walk frame changed canvas")
            let alpha = PetBitmap(source: frame, pixelWidth: 896, pixelHeight: 640)!
            check((0..<896).allSatisfy { alpha.alpha(x: $0, y: 639) == 0 }, "Walking feet clipped at canvas bottom")
            check((0..<640).allSatisfy { alpha.alpha(x: 0, y: $0) == 0 && alpha.alpha(x: 895, y: $0) == 0 }, "Tail clipped at canvas edge")
            let data = SpriteComponentCleanup.rgba(frame)
            var minWarmWidth = Int.max
            for y in 526...545 {
                var warm = 0
                for x in 260..<630 {
                    let i = (y * frame.width + x) * 4
                    if data[i + 3] > 180 && Int(data[i]) + 8 >= Int(data[i + 1]) && Int(data[i + 1]) + 15 >= Int(data[i + 2]) { warm += 1 }
                }
                minWarmWidth = min(minWarmWidth, warm)
            }
            check(minWarmWidth >= 12, "Horizontal hole through hem/thighs")

        }
        // Compare both illustrated half cycles so the opposite footfall cannot
        // silently introduce a more saturated hair/costume palette again.
        func paletteSaturation(_ frame: CGImage) -> (Double, Double) {
            let data = SpriteComponentCleanup.rgba(frame)
            var blue = 0.0, orange = 0.0, blueCount = 0.0, orangeCount = 0.0
            for y in 50..<630 { for x in 20..<700 {
                let i = (y * frame.width + x) * 4
                guard data[i + 3] >= 240 else { continue }
                let r = Double(data[i]), g = Double(data[i + 1]), b = Double(data[i + 2])
                let maximum = max(r, g, b), minimum = min(r, g, b)
                let saturation = (maximum - minimum) / max(1, maximum)
                if y < 250 && b > r + 25 && b > g + 15 && b > 65 {
                    blue += saturation; blueCount += 1
                }
                if y > 430 && r > g + 35 && g > b + 15 && r > 150 && b < 150 {
                    orange += saturation; orangeCount += 1
                }
            } }
            check(blueCount > 100 && orangeCount > 100, "Palette sample missing")
            return (blue / blueCount, orange / orangeCount)
        }
        let palettes = rightFrames.map(paletteSaturation)
        let referenceBlue = palettes.prefix(4).map { $0.0 }.reduce(0, +) / 4
        let referenceOrange = palettes.prefix(4).map { $0.1 }.reduce(0, +) / 4
        for palette in palettes.suffix(4) {
            check(abs(palette.0 - referenceBlue) < 0.065, "Hair saturation jumps when switching feet")
            check(abs(palette.1 - referenceOrange) < 0.065, "Costume saturation jumps when switching feet")
        }

        let referencePalette = PetWalkPalette.samples(rightFrames[0], PetWalkPalette.rgba(rightFrames[0]))
        for (index, frame) in rightFrames.enumerated() where index >= 4 {
            let palette = PetWalkPalette.samples(frame, PetWalkPalette.rgba(frame))
            for family in 0..<2 {
                check(abs(palette[family].hue - referencePalette[family].hue) < 0.02, "Walk color hue jumps")
            }
            let file = Bundle.module.url(forResource: "hoodie_walk_right_\(index)", withExtension: "png")!
            let raw = NSImage(contentsOf: file)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let original = PetWalkPalette.rgba(raw), corrected = PetWalkPalette.rgba(frame)
            check(stride(from: 3, to: original.count, by: 4).allSatisfy {
                original[$0] == corrected[$0]
            }, "Palette correction changed silhouette transparency")
        }
        print("PASS: half-cycle hair/costume saturation and hue continuity; correction preserves every alpha pixel")

        func faceCenter(_ image: CGImage) -> CGPoint {
            let bitmap = PetBitmap(source: image, pixelWidth: 896, pixelHeight: 640)!
            let bytes = bitmap.image.dataProvider!.data!
            let data = CFDataGetBytePtr(bytes)!
            var xSum = 0.0, ySum = 0.0, count = 0.0
            for y in stride(from: 160, to: 370, by: 2) {
                for x in stride(from: 80, to: 820, by: 2) {
                    let i = y * bitmap.image.bytesPerRow + x * 4
                    let r = Int(data[i + 1]), g = Int(data[i + 2]), b = Int(data[i + 3])
                    if data[i] > 240 && r > 185 && g > 135 && b > 110 && r > g + 8 && g > b + 4 && r - g < 65 {
                        xSum += Double(x); ySum += Double(y); count += 1
                    }
                }
            }
            check(count > 50, "Face missing from walking frame")
            return CGPoint(x: xSum / count, y: ySum / count)
        }
        let faces = (rightFrames + leftFrames).map(faceCenter)
        check(faces.map(\.x).max()! - faces.map(\.x).min()! < 12, "Horizontal head jitter")
        check(faces.map(\.y).max()! - faces.map(\.y).min()! < 12, "Vertical head jitter")
        check(PetWalkRenderer.resourceName(frame: 9, facingLeft: true) == "hoodie_walk_left_1", "Frame index does not wrap")
        check(PetWalkMotion.frame(distance: 0, height: 240) == 0, "Bad phase start")
        check(PetWalkMotion.frame(distance: 57.6, height: 240) == 0, "Stride does not loop")
        check(PetWalkMotion.frame(distance: 7.2, height: 240) == 1, "Phase not tied to travel distance")
        let at60 = (0..<60).reduce(CGFloat.zero) { distance, _ in distance + PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 1.0 / 60.0) }
        let at30 = (0..<30).reduce(CGFloat.zero) { distance, _ in distance + PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 1.0 / 30.0) }
        check(abs(at60 - at30) < 0.001 && abs(at60 - 48) < 0.001, "Walking speed depends on timer frequency")
        check(PetWalkMotion.step(remaining: -1, height: 240, elapsed: 1) == -1, "Movement overshoots destination")
        check(PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 20) <= 2.401, "Wake-up jump")
        view.mode = .hover
        view.walking = true
        view.advanceWalk(by: 7.2)
        check(view.walkFrame == 1 && view.isTransitioningPose, "View did not advance gait or transition")
        view.walking = false
        view.walking = true
        check(view.walkFrame == 0, "New walk did not restart gait")
        view.walking = false
        let preview = URL(fileURLWithPath: "/tmp/hoodie-walk-preview.gif")
        let gif = CGImageDestinationCreateWithURL(preview as CFURL, "com.compuserve.gif" as CFString, 16, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in rightFrames + leftFrames {
            let small = PetBitmap(source: frame, pixelWidth: 336, pixelHeight: 240)!
            CGImageDestinationAddImage(gif, small.image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: PetWalkMotion.cycleDuration(height: 240) / Double(PetWalkMotion.frameCount)]] as CFDictionary)
        }
        check(CGImageDestinationFinalize(gif), "GIF preview failed")
        for (index, frame) in rightFrames.enumerated() {
            try png(frame).write(to: URL(fileURLWithPath: "/tmp/hoodie-walk-frame-\(index).png"))
        }
        try png(leftFrames[2]).write(to: URL(fileURLWithPath: "/tmp/hoodie-walk-left.png"))
        print("PASS: eight intact full-body poses, slow gait, unclipped feet/tail, both directions, pose transitions, distance-based phase, timer-independent speed, no overshoot or wake-up teleport")
        let suite = "BaifanYuSkinTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: AppSettings.Key.skinIndex)
        AppSettings.adoptHoodieDefaultIfNeeded(in: defaults)
        check(defaults.integer(forKey: AppSettings.Key.skinIndex) == hoodie.index, "Existing settings did not adopt hoodie")
        defaults.set(1, forKey: AppSettings.Key.skinIndex)
        AppSettings.adoptHoodieDefaultIfNeeded(in: defaults)
        check(defaults.integer(forKey: AppSettings.Key.skinIndex) == 1, "Manual choice overwritten on relaunch")
        print("PASS: default migration, later manual choice, bundled skins, idle/happy cycling, matching transparent canvases, rotated head geometry and bundled license")
    }
}
