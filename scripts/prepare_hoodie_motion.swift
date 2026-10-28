#!/usr/bin/env swift
// Slice generated 4x2 animation sheets; align the face across frames without cropping art.
import AppKit
import CoreGraphics


// Remove only low-alpha, highly saturated generator fringe outside normal outlines.
func cleanAlphaFringe(_ source: CGImage) -> CGImage {
    let w = source.width, h = source.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    return bytes.withUnsafeMutableBytes { memory in
        let ctx = CGContext(data: memory.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = memory.bindMemory(to: UInt8.self)
        for i in stride(from: 0, to: data.count, by: 4) {
            let alpha = Int(data[i + 3])
            guard alpha > 0 && alpha < 240 else { continue }
            let r = Int(data[i]) * 255 / alpha, g = Int(data[i + 1]) * 255 / alpha, b = Int(data[i + 2]) * 255 / alpha
            if max(r, g, b) - min(r, g, b) > 165 {
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = 0
            }
        }
        return ctx.makeImage()!
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDir = root.appendingPathComponent("artwork-src/claude-hoodie/motion-v3")
let resources = root.appendingPathComponent("Sources/Resources")
func load(_ path: URL) -> CGImage {
    guard let image = NSImage(contentsOf: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Cannot load \(path.path)") }
    return cleanAlphaFringe(cg)
}
struct Features {
    let bounds: CGRect
    let face: CGPoint
}
func features(_ image: CGImage) -> Features {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { ptr in
        let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 40 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard minX < maxX, minY < maxY else { fatalError("Empty sprite") }
    let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    var sx = 0.0, sy = 0.0, count = 0.0
    let top = minY + Int(bounds.height * 0.20), bottom = min(h, minY + Int(bounds.height * 0.59))
    for y in top..<bottom { for x in minX...maxX {
        let i = (y * w + x) * 4
        let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
        if bytes[i + 3] > 240 && r > 185 && g > 135 && b > 110 && r > g + 8 && g > b + 4 && r - g < 65 {
            sx += Double(x); sy += Double(y); count += 1
        }
    } }
    guard count > 20 else { fatalError("Face alignment failed") }
    return Features(bounds: bounds, face: CGPoint(x: sx / count, y: sy / count))
}
let idle = load(resources.appendingPathComponent("hoodie_stand.png"))
let anchor = features(idle).face
var sprites: [(String, CGImage, Features)] = []
// Match head size before face alignment; the two independently illustrated
// half cycles have different source resolutions. Preserve every body pixel.
var canonicalHeadHeight: CGFloat?
func normalizedPose(_ image: CGImage) -> CGImage {
    let f = features(image)
    let headHeight = f.face.y - f.bounds.minY
    if canonicalHeadHeight == nil { canonicalHeadHeight = headHeight }
    let ratio = canonicalHeadHeight! / max(1, headHeight)
    let ctx = CGContext(data: nil, width: 640, height: 640, bitsPerComponent: 8,
        bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let top = 260 - f.face.y * ratio
    ctx.draw(image, in: CGRect(x: 320 - f.face.x * ratio,
        y: 640 - top - CGFloat(image.height) * ratio,
        width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio))
    return ctx.makeImage()!
}
for direction in ["right", "left"] {
    let v4 = root.appendingPathComponent("artwork-src/claude-hoodie/motion-v4/walk-right-alternating.png")
    let usesCanonical = FileManager.default.fileExists(atPath: v4.path)
    let sheet = load(usesCanonical ? v4 : sourceDir.appendingPathComponent("walk-\(direction)-sheet.png"))
    for frame in 0..<8 {
        let col = frame % 4, row = frame / 4
        let x0 = sheet.width * col / 4, x1 = sheet.width * (col + 1) / 4
        let y0 = sheet.height * row / 2, y1 = sheet.height * (row + 1) / 2
        var tile = sheet.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
        let correctedColors = root.appendingPathComponent("artwork-src/claude-hoodie/motion-v6/opposite-half-colors-final.png")
        let opposite = FileManager.default.fileExists(atPath: correctedColors.path) ? correctedColors : root.appendingPathComponent("artwork-src/claude-hoodie/motion-v5/opposite-half-sheet.png")
        if frame >= 4 && FileManager.default.fileExists(atPath: opposite.path) {
            let half = load(opposite)
            let i = frame - 4
            let col = i % 2, row = i / 2
            let x = half.width * col / 2, y = half.height * row / 2
            tile = half.cropping(to: CGRect(x: x, y: y,
                width: half.width * (col + 1) / 2 - x,
                height: half.height * (row + 1) / 2 - y))!
        }
        tile = normalizedPose(tile)
        if usesCanonical && direction == "left" {
            let ctx = CGContext(data: nil, width: tile.width, height: tile.height, bitsPerComponent: 8,
                                bytesPerRow: tile.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: CGFloat(tile.width), y: 0); ctx.scaleBy(x: -1, y: 1)
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: tile.width, height: tile.height))
            tile = ctx.makeImage()!
        }
        sprites.append(("hoodie_walk_\(direction)_\(frame)", tile, features(tile)))
    }
}
// Re-typeset the tiny badge after generation so all 16 frames say Claude.
func correctedBadge(_ image: CGImage, face: CGPoint, fallback: CGRect? = nil) -> (CGImage, Bool) {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { memory in
        let ctx = CGContext(data: memory.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var runs: [(y: Int, x0: Int, x1: Int)] = []
    let x0 = max(0, Int(face.x) - 55), x1 = min(w - 1, Int(face.x) + 55)
    for y in max(0, Int(face.y) + 80)..<min(h, Int(face.y) + 150) {
        var start: Int?
        for x in x0...x1 {
            let i = (y * w + x) * 4
            let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
            let orange = bytes[i + 3] > 240 && r > 140 && g > 70 && g < 210 && b < 160 && r - g > 25 && g - b > 15
            if orange { if start == nil { start = x } }
            else if let from = start {
                if x - from >= 12 { runs.append((y, from, x - 1)) }
                start = nil
            }
        }
    }
    var selected: CGRect?
    for top in runs { for bottom in runs {
        let dy = bottom.y - top.y
        guard dy >= 13 && dy <= 38,
              abs((top.x0 + top.x1) - (bottom.x0 + bottom.x1)) < 20 else { continue }
        let rect = CGRect(x: min(top.x0, bottom.x0) - 1, y: top.y - 1,
                          width: max(top.x1, bottom.x1) - min(top.x0, bottom.x0) + 3, height: dy + 3)
        let ratio = rect.width / rect.height
        guard rect.width >= 25, ratio >= 1.6, ratio <= 3.2, abs(rect.midX - face.x) <= 30 else { continue }
        if selected == nil || abs(ratio - 2.0) < abs(selected!.width / selected!.height - 2.0) { selected = rect }
    } }
    if selected == nil { selected = fallback }
    guard let rect = selected, rect.width >= 25 && rect.width < 90 else { return (image, false) }
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let native = CGRect(x: rect.minX, y: CGFloat(h) - rect.maxY, width: rect.width, height: rect.height)
    let path = CGPath(roundedRect: native, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.96, blue: 0.89, alpha: 1).cgColor)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.72, green: 0.46, blue: 0.25, alpha: 1).cgColor)
    ctx.setLineWidth(1.5)
    ctx.drawPath(using: .fillStroke)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let text = NSAttributedString(string: "Claude", attributes: [
        .font: NSFont.systemFont(ofSize: min(native.height * 0.48, native.width * 0.23), weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.17, blue: 0.12, alpha: 1)
    ])
    let size = text.size()
    text.draw(at: CGPoint(x: native.midX - size.width / 2, y: native.midY - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    return (ctx.makeImage()!, true)
}
var correctedBadges = 0
let width = 896, height = 640
var scale: CGFloat = 10
for (_, _, feature) in sprites {
    let b = feature.bounds, face = feature.face
    scale = min(scale, (anchor.x - 8) / max(1, face.x - b.minX),
                (CGFloat(width) - 8 - anchor.x) / max(1, b.maxX - face.x),
                (anchor.y - 8) / max(1, face.y - b.minY),
                (CGFloat(height) - 8 - anchor.y) / max(1, b.maxY - face.y))
}
for (name, image, feature) in sprites {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let x = anchor.x - feature.face.x * scale
    let top = anchor.y - feature.face.y * scale
    ctx.draw(image, in: CGRect(x: x, y: CGFloat(height) - top - CGFloat(image.height) * scale,
                              width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
    // Visible alpha bounds already have an 8px safety margin. Clear only the
    // outer 4px gutter to remove near-transparent generation speckles there.
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: 4))
    ctx.clear(CGRect(x: 0, y: height - 4, width: width, height: 4))
    ctx.clear(CGRect(x: 0, y: 0, width: 4, height: height))
    ctx.clear(CGRect(x: width - 4, y: 0, width: 4, height: height))
    // One generated badge has a broken orange outline, so use its reviewed
    // bounds when automatic rectangle detection fails (also on the mirror).
    let badgeFallback: CGRect? = (name.hasSuffix("_4") || name.hasSuffix("_5")) ? CGRect(
        x: anchor.x + (name.contains("left") ? -14 : 14) - 29,
        y: anchor.y + 72, width: 58, height: 30) : nil
    let (finished, didCorrect) = correctedBadge(ctx.makeImage()!, face: anchor, fallback: badgeFallback)
    if didCorrect { correctedBadges += 1 } else { print("Unchanged badge: \(name)") }
    let rep = NSBitmapImageRep(cgImage: finished)
    try rep.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent(name + ".png"))
}
print("Prepared \(sprites.count) three-quarter walk frames, common scale \(scale), face anchor \(anchor), corrected badges \(correctedBadges)")
