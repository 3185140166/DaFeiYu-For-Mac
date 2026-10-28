import AppKit
import CoreGraphics

extension Bundle {
    /// SPM's generated accessor searches the app root and then the development
    /// checkout; packaged apps must resolve their own Contents/Resources first.
    static var petResources: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("BaifanYu_BaifanYu.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return .module
    }
}

/// A CGImage together with the raw ARGB buffer it was rendered into.
///
/// Two reasons for keeping the buffer instead of just the image:
///  1. transparent pixels can be hit-tested cheaply (no NSColor per mouse move);
///  2. the artwork is pre-scaled once per size, so the 30 Hz draw is a plain
///     blit instead of a 5× downscale of a 1 MB PNG.
///
/// Buffer layout (verified on this machine): row 0 is the image's TOP row and
/// the first byte of each pixel is alpha — premultipliedFirst + byteOrder32Big.
final class PetBitmap {
    let image: CGImage
    let pixelWidth: Int
    let pixelHeight: Int

    private let buffer: UnsafeMutablePointer<UInt8>
    private let bytesPerRow: Int

    init?(source: CGImage, pixelWidth: Int, pixelHeight: Int) {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let bytesPerRow = pixelWidth * 4
        let byteCount = bytesPerRow * pixelHeight
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        buffer.initialize(repeating: 0, count: byteCount)

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: buffer, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
            buffer.deallocate()
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let out = ctx.makeImage() else {
            buffer.deallocate()
            return nil
        }
        self.image = out
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.buffer = buffer
        self.bytesPerRow = bytesPerRow
    }

    /// Rotate 90° clockwise, crop to the given fractions of the *original*, then
    /// scale the result to the requested pixel size — all in one pass.
    ///
    /// `crop` is expressed in top-left-origin fractions of the source image
    /// (same convention as Android's `Bitmap.createBitmap` + `Matrix.postRotate(90)`).
    static func perched(source: CGImage, crop: CGRect, pixelWidth: Int, pixelHeight: Int) -> PetBitmap? {
        let sw = CGFloat(source.width), sh = CGFloat(source.height)
        let cropRect = CGRect(x: crop.origin.x * sw,
                              y: crop.origin.y * sh,
                              width: crop.width * sw,
                              height: crop.height * sh).integral
        guard let cropped = source.cropping(to: cropRect) else { return nil }
        let cw = CGFloat(cropped.width), ch = CGFloat(cropped.height)
        guard cw > 0, ch > 0, pixelWidth > 0, pixelHeight > 0 else { return nil }

        let bytesPerRow = pixelWidth * 4
        let byteCount = bytesPerRow * pixelHeight
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        buffer.initialize(repeating: 0, count: byteCount)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: buffer, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
            buffer.deallocate()
            return nil
        }
        ctx.interpolationQuality = .high
        // Scale last so it applies to the rotated result, then rotate 90° CW.
        ctx.scaleBy(x: CGFloat(pixelWidth) / ch, y: CGFloat(pixelHeight) / cw)
        ctx.translateBy(x: 0, y: cw)
        ctx.rotate(by: -.pi / 2)
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cw, height: ch))
        guard let out = ctx.makeImage() else {
            buffer.deallocate()
            return nil
        }
        let bitmap = PetBitmap(image: out, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                               buffer: buffer, bytesPerRow: bytesPerRow)
        return bitmap
    }

    private init(image: CGImage, pixelWidth: Int, pixelHeight: Int,
                 buffer: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.buffer = buffer
        self.bytesPerRow = bytesPerRow
    }

    /// Alpha of the pixel at (x, y) with the origin at the image's top-left,
    /// matching the flipped view coordinate space.
    func alpha(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < pixelWidth, y < pixelHeight else { return 0 }
        return buffer[y * bytesPerRow + x * 4]
    }

    /// Is there anything visible around (normalised) point `p` in this artwork?
    func isOpaque(atNormalized p: CGPoint, threshold: UInt8 = 26) -> Bool {
        let x = Int(p.x * CGFloat(pixelWidth))
        let y = Int(p.y * CGFloat(pixelHeight))
        return alpha(x: x, y: y) > threshold
    }

    deinit { buffer.deallocate() }
}

/// Match generated half-cycle colors once when decoding, never during a draw.
/// Only hue/saturation are adjusted; geometry, value and alpha stay intact.
enum PetWalkPalette {
    struct HSV {
        var h: Double; var s: Double; var v: Double
    }
    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> HSV {
        let hi = max(r, g, b), lo = min(r, g, b), delta = hi - lo
        var h = 0.0
        if delta > 0 {
            if hi == r { h = (g - b) / delta }
            else if hi == g { h = 2 + (b - r) / delta }
            else { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        return HSV(h: h, s: hi > 0 ? delta / hi : 0, v: hi)
    }
    static func rgb(_ c: HSV) -> (Double, Double, Double) {
        let h = (c.h - floor(c.h)) * 6
        let f = h - floor(h), p = c.v * (1 - c.s)
        let q = c.v * (1 - c.s * f), t = c.v * (1 - c.s * (1 - f))
        switch Int(h) % 6 {
        case 0: return (c.v, t, p)
        case 1: return (q, c.v, p)
        case 2: return (p, c.v, t)
        case 3: return (p, q, c.v)
        case 4: return (t, p, c.v)
        default: return (c.v, p, q)
        }
    }
    struct Sample { var hue: Double; var saturation: Double }
    static func samples(_ image: CGImage, _ bytes: [UInt8]) -> [Sample] {
        var sums = [(h: 0.0, s: 0.0, n: 0.0), (h: 0.0, s: 0.0, n: 0.0)]
        for y in 50..<min(630, image.height) { for x in 20..<min(700, image.width) {
            let i = (y * image.width + x) * 4
            guard bytes[i + 3] >= 240 else { continue }
            let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
            var family: Int?
            if y < 250 && b > r + 25 && b > g + 15 && b > 65 { family = 0 }
            if y > 430 && r > g + 35 && g > b + 15 && r > 150 && b < 150 { family = 1 }
            if let family {
                let color = hsv(r, g, b)
                sums[family].h += color.h; sums[family].s += color.s; sums[family].n += 1
            }
        } }
        return sums.map { Sample(hue: $0.h / max(1, $0.n), saturation: $0.s / max(1, $0.n)) }
    }
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { memory in
            let ctx = CGContext(data: memory.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    static func matched(_ image: CGImage, reference: CGImage) -> CGImage {
        var bytes = rgba(image)
        let source = samples(image, bytes), target = samples(reference, rgba(reference))
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[i + 3])
            guard alpha > 0 else { continue }
            var color = hsv(Double(bytes[i]) / alpha, Double(bytes[i + 1]) / alpha, Double(bytes[i + 2]) / alpha)
            // Smooth hue membership avoids introducing hard color boundaries.
            let blue = max(0, min(1, (color.h - 0.48) / 0.06, (0.79 - color.h) / 0.06))
            let orange = max(0, min(1, (color.h - 0.005) / 0.035, (0.17 - color.h) / 0.04))
                * max(0, min(1, (color.s - 0.25) / 0.20))
            for (family, weight) in [(0, blue), (1, orange)] where weight > 0 {
                let gain = target[family].saturation / max(0.01, source[family].saturation)
                color.s = min(1, color.s * (1 + (gain - 1) * weight))
                color.h += (target[family].hue - source[family].hue) * weight
            }
            let (r, g, b) = rgb(color)
            bytes[i] = UInt8(max(0, min(alpha, (r * alpha).rounded())))
            bytes[i + 1] = UInt8(max(0, min(alpha, (g * alpha).rounded())))
            bytes[i + 2] = UInt8(max(0, min(alpha, (b * alpha).rounded())))
        }
        return bytes.withUnsafeMutableBytes { memory in
            let ctx = CGContext(data: memory.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            return ctx.makeImage()!
        }
    }
}

/// Loads artwork from the SPM resource bundle and caches the pre-scaled,
/// pre-rotated bitmaps. Cache keys include the pixel size so a slider drag
/// rebuilds at most once per quantised step.
@MainActor
final class PetArtworkStore {
    static let shared = PetArtworkStore()

    private var sources: [String: CGImage] = [:]
    private var cache: [String: PetBitmap] = [:]
    private var misses: Set<String> = []
    private var walkSources: [String: [CGImage]] = [:]
    private var walkRasterCache: [String: PetBitmap] = [:]
    private var walkRasterHeight: Int?

    private init() {}

    // MARK: - Source artwork

    /// The original, full-resolution standing or expression image of a skin.
    func sourceImage(skin: PetSkin, expression: Int) -> CGImage? {
        sourceImage(named: skin.resourceName(for: expression))
    }

    private func sourceImage(named name: String) -> CGImage? {
        if let hit = sources[name] { return hit }
        if misses.contains(name) { return nil }

        guard let url = Bundle.petResources.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            misses.insert(name)
            return nil
        }
        sources[name] = cg
        return cg
    }

    func hasArtwork(skin: PetSkin, expression: Int) -> Bool {
        sourceImage(skin: skin, expression: expression) != nil
    }

    /// How many expressions of a skin actually load.
    func availableExpressionCount(skin: PetSkin) -> Int {
        (1...skin.expressionCount).filter { hasArtwork(skin: skin, expression: $0) }.count
    }

    // MARK: - Scaled / rotated artwork

    /// Her whole body, scaled to `pixelHeight`.
    func hoverArtwork(skin: PetSkin, expression: Int, pixelHeight: Int) -> PetBitmap? {
        guard let source = sourceImage(skin: skin, expression: expression) else { return nil }
        let h = max(4, pixelHeight)
        let w = max(4, Int((CGFloat(h) * CGFloat(source.width) / CGFloat(source.height)).rounded()))
        let key = "hover-\(skin.index)-\(expression)-\(h)"
        if let hit = cache[key] { return hit }
        cache[key] = PetBitmap(source: source, pixelWidth: w, pixelHeight: h)
        return cache[key]
    }

    /// Her head only, rotated 90° and scaled so the drawn width is `pixelWidth`.
    func perchArtwork(skin: PetSkin, expression: Int, pixelWidth: Int, aspect: CGFloat) -> PetBitmap? {
        guard let source = sourceImage(skin: skin, expression: expression) else { return nil }
        let w = max(4, pixelWidth)
        let h = max(4, Int((CGFloat(w) * aspect).rounded()))
        let key = "perch-\(skin.index)-\(expression)-\(w)"
        if let hit = cache[key] { return hit }
        let crop = CGRect(x: skin.headX0, y: skin.headY0,
                          width: skin.headX1 - skin.headX0, height: skin.headY1 - skin.headY0)
        cache[key] = PetBitmap.perched(source: source, crop: crop, pixelWidth: w, pixelHeight: h)
        return cache[key]
    }

    func walkFrames(skin: PetSkin, facingLeft: Bool) -> [CGImage] {
        guard skin.prefix == "hoodie" else { return [] }
        let key = "walk-\(skin.index)-\(facingLeft)"
        if let frames = walkSources[key] { return frames }
        let frames = (0..<PetWalkMotion.frameCount).compactMap {
            sourceImage(named: PetWalkRenderer.resourceName(frame: $0, facingLeft: facingLeft))
        }
        let matched: [CGImage]
        if frames.count == PetWalkMotion.frameCount {
            matched = frames.enumerated().map { index, frame in
                index >= 4 ? PetWalkPalette.matched(frame, reference: frames[0]) : frame
            }
        } else { matched = frames }
        walkSources[key] = matched
        return matched
    }

    /// Direction-specific art; the left-facing badge is not mirror-flipped.
    func walkArtwork(skin: PetSkin, frame: Int, facingLeft: Bool, pixelHeight: Int) -> PetBitmap? {
        let frames = walkFrames(skin: skin, facingLeft: facingLeft)
        guard frames.count == PetWalkMotion.frameCount, let source = frames.first else { return nil }
        let directionKey = "walk-\(skin.index)-\(facingLeft)"
        let frame = ((frame % frames.count) + frames.count) % frames.count
        let h = max(4, pixelHeight)
        if walkRasterHeight != h {
            walkRasterCache.removeAll()
            walkRasterHeight = h
        }
        let key = "\(directionKey)-\(frame)-\(h)"
        if let hit = walkRasterCache[key] { return hit }
        let w = max(4, Int((CGFloat(h) * CGFloat(source.width) / CGFloat(source.height)).rounded()))
        let bitmap = PetBitmap(source: frames[frame], pixelWidth: w, pixelHeight: h)
        walkRasterCache[key] = bitmap
        return bitmap
    }

    /// Drop everything (after a skin switch there is nothing worth keeping).
    func purge() {
        walkSources.removeAll()
        walkRasterCache.removeAll()
        walkRasterHeight = nil
        cache.removeAll()
    }
}
