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
        check(rightFrames.count == PetWalkMotion.frameCount && leftFrames.count == PetWalkMotion.frameCount, "Missing walk directions or frames")
        func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }
        check(Set(rightFrames.map(png)).count == PetWalkMotion.frameCount, "Gait frames do not advance through distinct leg poses")
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
            // Flood from the skirt through the visible lower body. A detached
            // shoe or skin strip must not pass merely because other leg exists.
            let w = frame.width, top = 510, bottom = 630, x0 = 270, x1 = 580
            var visited = [Bool](repeating: false, count: w * frame.height)
            var queue: [Int] = []
            for x in x0..<x1 where data[(top * w + x) * 4 + 3] > 80 {
                let pixel = top * w + x; visited[pixel] = true; queue.append(pixel)
            }
            var head = 0
            while head < queue.count {
                let pixel = queue[head]; head += 1
                let x = pixel % w, y = pixel / w
                for yy in max(top, y - 1)...min(bottom - 1, y + 1) {
                    for xx in max(x0, x - 1)...min(x1 - 1, x + 1) {
                        let next = yy * w + xx
                        if !visited[next] && data[next * 4 + 3] > 80 {
                            visited[next] = true; queue.append(next)
                        }
                    }
                }
            }
            var disconnected = 0, exposedSkin = 0
            for y in 540..<bottom { for x in x0..<x1 {
                let pixel = y * w + x, i = pixel * 4
                if data[i + 3] > 200 && !visited[pixel] { disconnected += 1 }
                if y < 580 && data[i + 3] > 240 && data[i] > 240 && data[i + 1] > 190 && data[i + 1] < 240 && data[i + 2] > 160 && data[i + 2] < 225 {
                    exposedSkin += 1
                }
            } }
            check(disconnected < 8, "Lower limb/shoe disconnected from skirt")
            check(exposedSkin > 250, "Shoes conceal the visible legs")


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

        // The face, hair and costume are literally the same pixels in every
        // rendered frame, not independently regenerated full-body poses.
        let firstPixels = SpriteComponentCleanup.rgba(rightFrames[0])
        for frame in rightFrames.dropFirst() {
            let pixels = SpriteComponentCleanup.rgba(frame)
            check(pixels[0..<(480 * 896 * 4)].elementsEqual(firstPixels[0..<(480 * 896 * 4)]), "Pocket torso changes between footfalls")
        }
        print("PASS: hands-in-pocket torso stays pixel-identical throughout the walk")
        // Bound adjacent rendered lower-body changes, including the wrap.
        // Count changed opaque pixels: swapped contact poses cause a large spike.
        var changedCounts: [Int] = []
        for i in rightFrames.indices {
            let a = SpriteComponentCleanup.rgba(rightFrames[i])
            let b = SpriteComponentCleanup.rgba(rightFrames[(i + 1) % rightFrames.count])
            var changed = 0
            for pixel in (530 * 896)..<(630 * 896) {
                let offset = pixel * 4
                if abs(Int(a[offset + 3]) - Int(b[offset + 3])) > 100 { changed += 1 }
            }
            changedCounts.append(changed)
        }
        let typicalChange = changedCounts.sorted()[changedCounts.count / 2]
        check(Double(changedCounts.max()!) < Double(typicalChange) * 2.25,
              "Rendered foot silhouette has an isolated jump between poses")
        print("PASS: identical pocket-torso pixels; bounded adjacent foot motion including cycle wrap")
        for far in [false, true] {
            let start = PetWalkMotion.footPose(phase: 0, far: far)
            let wrap = PetWalkMotion.footPose(phase: 1 - 0.00001, far: far)
            check(abs(start.x - wrap.x) < 0.01 && abs(start.lift - wrap.lift) < 0.01, "Foot trajectory jumps at wrap")
            let passing = PetWalkMotion.footPose(phase: far ? 0.3 : 0.8, far: far)
            check(abs(passing.x) < 0.01 && passing.lift > 14, "Swing leg never passes beneath hip")
        }

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
        check(PetWalkRenderer.resourceName(frame: 25, facingLeft: true) == "hoodie_walk_left_1", "Frame index does not wrap")
        check(PetWalkMotion.frame(distance: 0, height: 240) == 0, "Bad phase start")
        check(PetWalkMotion.frame(distance: 34.56, height: 240) == 0, "Stride does not loop")
        check(PetWalkMotion.frame(distance: 2.4, height: 240) == 1, "Phase not tied to travel distance")
        let at60 = (0..<60).reduce(CGFloat.zero) { distance, _ in distance + PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 1.0 / 60.0) }
        let at30 = (0..<30).reduce(CGFloat.zero) { distance, _ in distance + PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 1.0 / 30.0) }
        check(abs(at60 - at30) < 0.001 && abs(at60 - 28.8) < 0.001, "Walking speed depends on timer frequency")
        check(PetWalkMotion.step(remaining: -1, height: 240, elapsed: 1) == -1, "Movement overshoots destination")
        check(PetWalkMotion.step(remaining: 1000, height: 240, elapsed: 20) <= 1.441, "Wake-up jump")
        view.mode = .hover
        view.walking = true
        view.advanceWalk(by: 2.4)
        check(view.walkFrame == 1 && view.isTransitioningPose, "View did not advance gait or transition")
        view.walking = false
        view.walking = true
        check(view.walkFrame == 0, "New walk did not restart gait")
        view.walking = false
        let preview = URL(fileURLWithPath: "/tmp/hoodie-walk-preview.gif")
        let gif = CGImageDestinationCreateWithURL(preview as CFURL, "com.compuserve.gif" as CFString, PetWalkMotion.frameCount * 2, nil)!
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
        print("PASS: 24 continuous layered poses, slow gait, unclipped feet/tail, both directions, pose transitions, distance-based phase, timer-independent speed, no overshoot or wake-up teleport")
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
