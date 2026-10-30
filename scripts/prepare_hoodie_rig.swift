import AppKit
import CoreGraphics

@main struct PrepareRig {
    static let width = 896, height = 640
    static func load(_ path: String, trimGlow: Bool = false) -> CGImage {
        let image = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var bytes = SpriteComponentCleanup.rgba(image)
        if trimGlow {
            // Generated glow is translucent; retain only the solid sprite and
            // a one-pixel antialias fringe around it. Never classify body color.
            let w = image.width, h = image.height
            let solid = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] >= 245 }
            for y in 0..<h { for x in 0..<w {
                var keep = false
                for dy in -1...1 { for dx in -1...1 {
                    let px = x + dx, py = y + dy
                    if px >= 0 && px < w && py >= 0 && py < h && solid[py * w + px] { keep = true }
                } }
                if !keep { for c in 0..<4 { bytes[(y * w + x) * 4 + c] = 0 } }
            } }
        }
        return SpriteComponentCleanup.image(&bytes, width: image.width, height: image.height)
    }
    static func bounds(_ image: CGImage) -> CGRect {
        let data = SpriteComponentCleanup.rgba(image), w = image.width, h = image.height
        var x0 = w, y0 = h, x1 = 0, y1 = 0
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 40 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        } }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
    static func face(_ image: CGImage) -> CGPoint {
        let b = bounds(image), data = SpriteComponentCleanup.rgba(image), w = image.width
        var sx = 0.0, sy = 0.0, count = 0.0
        for y in Int(b.minY + b.height * 0.25)..<Int(b.minY + b.height * 0.57) {
            for x in Int(b.minX)..<Int(b.maxX) {
                let i = (y * w + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1]), blue = Int(data[i + 2])
                if data[i + 3] > 240 && r > 185 && g > 135 && blue > 110 && r > g + 8 && g > blue + 4 && r - g < 65 {
                    sx += Double(x); sy += Double(y); count += 1
                }
            }
        }
        precondition(count > 100)
        return CGPoint(x: sx / count, y: sy / count)
    }
    static func draw(_ image: CGImage, rect: CGRect, in ctx: CGContext) {
        ctx.saveGState(); ctx.translateBy(x: 0, y: rect.minY + rect.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: rect); ctx.restoreGState()
    }
    static func main() throws {
        let resources = "Sources/Resources/"
        let body = load("artwork-src/claude-hoodie/motion-v12/pocket-body.png")
        let limb = load("artwork-src/claude-hoodie/motion-v13/puffy-shoe.png", trimGlow: true)
        let boot = limb.cropping(to: bounds(limb))!
        let f = face(body), b = bounds(body)
        let ratio = 274 / (f.y - b.minY)
        let rect = CGRect(x: 408.4 - f.x * ratio, y: 304.1 - f.y * ratio,
                          width: CGFloat(body.width) * ratio, height: CGFloat(body.height) * ratio)
        print("Body bounds", b, "face", f, "destination", rect)
        // Anchor the pelvis to the illustrated skirt, not to the face. In a
        // three-quarter pose the face is forward of the torso's actual center.
        let bodyPixels = SpriteComponentCleanup.rgba(body)
        var hemCenters: [CGFloat] = []
        for y in 0..<body.height {
            let destinationY = rect.minY + CGFloat(y) * ratio
            guard destinationY >= 485 && destinationY <= 515 else { continue }
            var left = CGFloat.greatestFiniteMagnitude, right: CGFloat = 0
            for x in 0..<body.width {
                let i = (y * body.width + x) * 4
                let r = Int(bodyPixels[i]), g = Int(bodyPixels[i + 1]), blue = Int(bodyPixels[i + 2])
                if bodyPixels[i + 3] > 240 && r > 150 && r - g > 25 && g - blue > 20 {
                    let destinationX = rect.minX + CGFloat(x) * ratio
                    left = min(left, destinationX); right = max(right, destinationX)
                }
            }
            if right - left > 120 { hemCenters.append((left + right) / 2) }
        }
        precondition(!hemCenters.isEmpty, "Cannot locate the illustrated skirt center")
        let hipCenter = hemCenters.sorted()[hemCenters.count / 2]
        print("Skirt/pelvis center:", hipCenter, "(previous hardcoded pelvis: 417)")

        let bodyContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bodyContext.interpolationQuality = .high
        bodyContext.translateBy(x: 0, y: CGFloat(height)); bodyContext.scaleBy(x: 1, y: -1)
        draw(body, rect: rect, in: bodyContext)
        let normalizedBody = bodyContext.makeImage()!
        for left in [false, true] { for frame in 0..<PetWalkMotion.frameCount {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
            if left { ctx.translateBy(x: 816.8, y: 0); ctx.scaleBy(x: -1, y: 1) }
            let phase = Double(frame) / Double(PetWalkMotion.frameCount)
            for far in [true, false] {
                let pose = PetWalkMotion.footPose(phase: phase, far: far)
                // Hip remains under the hem; the shoe's ankle opening is
                // joined by a thigh/knee/calf, not a detached textured stub.
                let hip = CGPoint(x: hipCenter + (far ? -16 : 16), y: 516)
                let footX = hip.x + pose.x
                let bootWidth: CGFloat = far ? 68 : 72
                let bootHeight = bootWidth * CGFloat(boot.height) / CGFloat(boot.width) * 0.78
                let top = 604 - bootHeight - pose.lift
                let ankle = CGPoint(x: footX, y: top + bootHeight * 0.30)
                // Place the knee between hip and ankle so shortening the leg
                // cannot leave an overlong shin or an abrupt bent skin strip.
                let knee = CGPoint(x: hip.x + pose.x * 0.50 + pose.lift * 0.20,
                                   y: (hip.y + ankle.y) * 0.50 + 3 - pose.lift * 0.12)
                let shoeRect = CGRect(x: footX - bootWidth * 0.36, y: top, width: bootWidth, height: bootHeight)
                // Rear cuff sits behind the leg, not over the whole shin.
                draw(boot, rect: shoeRect, in: ctx)
                let leg = CGMutablePath()
                leg.move(to: CGPoint(x: hip.x - 24, y: hip.y))
                leg.addQuadCurve(to: CGPoint(x: knee.x - 21, y: knee.y),
                                 control: CGPoint(x: hip.x - 24, y: (hip.y + knee.y) / 2))
                leg.addQuadCurve(to: CGPoint(x: ankle.x - 17, y: ankle.y + 4),
                                 control: CGPoint(x: knee.x - 20, y: (knee.y + ankle.y) / 2))
                leg.addLine(to: CGPoint(x: ankle.x + 18, y: ankle.y + 4))
                leg.addQuadCurve(to: CGPoint(x: knee.x + 21, y: knee.y),
                                 control: CGPoint(x: knee.x + 20, y: (knee.y + ankle.y) / 2))
                leg.addQuadCurve(to: CGPoint(x: hip.x + 24, y: hip.y),
                                 control: CGPoint(x: hip.x + 24, y: (hip.y + knee.y) / 2))
                leg.closeSubpath()
                ctx.saveGState()
                ctx.addPath(leg); ctx.clip()
                let shadow = NSColor(calibratedRed: far ? 0.94 : 0.98, green: far ? 0.77 : 0.82, blue: far ? 0.69 : 0.75, alpha: 1).cgColor
                let light = NSColor(calibratedRed: 1, green: far ? 0.87 : 0.91, blue: far ? 0.79 : 0.84, alpha: 1).cgColor
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [shadow, light, light] as CFArray, locations: [0, 0.45, 1])!
                ctx.drawLinearGradient(gradient, start: CGPoint(x: knee.x - 24, y: knee.y), end: CGPoint(x: knee.x + 24, y: knee.y), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                ctx.restoreGState()
                ctx.addPath(leg)
                ctx.setStrokeColor(NSColor(calibratedRed: 0.46, green: 0.25, blue: 0.20, alpha: 1).cgColor)
                ctx.setLineWidth(2.2); ctx.strokePath()
                // Restore only the front rim/sides. The open ankle oval lets
                // the leg remain visible in front of the rear cuff, while the
                // lower shin enters behind the front lip. Preserve side flower.
                ctx.saveGState()
                let frontCuff = CGMutablePath()
                frontCuff.addRect(shoeRect.insetBy(dx: -2, dy: -12))
                frontCuff.addEllipse(in: CGRect(x: ankle.x - 12, y: top - 8,
                    width: 24, height: bootHeight * 0.28 + 8))
                ctx.addPath(frontCuff); ctx.clip(using: .evenOdd)
                draw(boot, rect: shoeRect, in: ctx)
                ctx.restoreGState()
            }
            draw(normalizedBody, rect: CGRect(x: 0, y: 0, width: width, height: height), in: ctx)
            // Re-typeset the badge after mirroring the complete body.
            ctx.saveGState()
            if left { ctx.translateBy(x: 816.8, y: 0); ctx.scaleBy(x: -1, y: 1) }
            let badge = CGRect(x: left ? 371.8 : 381, y: 416, width: 64, height: 33)
            ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.96, blue: 0.89, alpha: 1).cgColor)
            ctx.setStrokeColor(NSColor.brown.cgColor); ctx.setLineWidth(1.2)
            ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.drawPath(using: .fillStroke)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ("Claude" as NSString).draw(in: badge.insetBy(dx: 5, dy: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.darkGray])
            NSGraphicsContext.restoreGraphicsState(); ctx.restoreGState()
            let image = ctx.makeImage()!
            let file = resources + "hoodie_walk_\(left ? "left" : "right")_\(frame).png"
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
        } }
        print("Prepared 24 continuous poses per direction from one fixed torso and two persistent legs")
    }
}
