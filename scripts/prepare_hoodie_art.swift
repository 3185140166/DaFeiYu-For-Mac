#!/usr/bin/env swift
// Normalize the selected licensed hoodie sprites onto matching transparent canvases.
// Pass --original to restore the untouched CrossPet poses.
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
let output = root.appendingPathComponent("Sources/Resources")
let side = 640
let canvasWidth = 896
func write(_ image: CGImage, to name: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: output.appendingPathComponent(name + ".png"))
}
for (source, destination) in [("idle", "hoodie_stand"), ("happy", "hoodie_face_happy")] {
    let relaxed = root.appendingPathComponent("artwork-src/claude-hoodie/motion-v3/idle-relaxed.png")
    let refined = root.appendingPathComponent("artwork-src/claude-hoodie/hand-refinement/\(source)-hands-v2.png")
    let original = root.appendingPathComponent("artwork-src/claude-hoodie/\(source).webp")
    let path: URL
    if CommandLine.arguments.contains("--original") { path = original }
    else if source == "idle", FileManager.default.fileExists(atPath: relaxed.path) { path = relaxed }
    else { path = FileManager.default.fileExists(atPath: refined.path) ? refined : original }
    guard let image = NSImage(contentsOf: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: canvasWidth, height: side, bitsPerComponent: 8,
                              bytesPerRow: canvasWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot read \(path.path)") }
    // Preserve the complete framing and alpha; use the same 640px canvas for both poses.
    let scale = min(CGFloat(side) / CGFloat(cg.width), CGFloat(side) / CGFloat(cg.height))
    let width = CGFloat(cg.width) * scale, height = CGFloat(cg.height) * scale
    let x = (CGFloat(canvasWidth) - width) / 2, y = (CGFloat(side) - height) / 2
    ctx.interpolationQuality = .high
    ctx.draw(cleanAlphaFringe(cg), in: CGRect(x: x, y: y, width: width, height: height))
    guard let aligned = ctx.makeImage() else { fatalError("Canvas failed") }
    try write(aligned, to: destination)
    if source == "idle" {
        let square = aligned.cropping(to: CGRect(x: (canvasWidth - side) / 2, y: 0, width: side, height: side))!
        try write(square, to: "header")
    }
    print("wrote \(destination).png")
}
