#!/usr/bin/env swift
// Normalize the selected licensed hoodie sprites onto matching transparent canvases.
// Pass --original to restore the untouched CrossPet poses.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Sources/Resources")
let side = 640
func write(_ image: CGImage, to name: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: output.appendingPathComponent(name + ".png"))
}
for (source, destination) in [("idle", "hoodie_stand"), ("happy", "hoodie_face_happy")] {
    let refined = root.appendingPathComponent("artwork-src/claude-hoodie/hand-refinement/\(source)-hands-v2.png")
    let original = root.appendingPathComponent("artwork-src/claude-hoodie/\(source).webp")
    let path = !CommandLine.arguments.contains("--original") && FileManager.default.fileExists(atPath: refined.path)
        ? refined : original
    guard let image = NSImage(contentsOf: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot read \(path.path)") }
    // Preserve the complete framing and alpha; use the same 640px canvas for both poses.
    let scale = min(CGFloat(side) / CGFloat(cg.width), CGFloat(side) / CGFloat(cg.height))
    let width = CGFloat(cg.width) * scale, height = CGFloat(cg.height) * scale
    let x = (CGFloat(side) - width) / 2, y = (CGFloat(side) - height) / 2
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: x, y: y, width: width, height: height))
    guard let aligned = ctx.makeImage() else { fatalError("Canvas failed") }
    try write(aligned, to: destination)
    if source == "idle" { try write(aligned, to: "header") }
    print("wrote \(destination).png")
}
