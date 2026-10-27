#!/usr/bin/env swift
// Reproducible, lossless canvas alignment of the two licensed CrossPet sources.
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
    let path = root.appendingPathComponent("artwork-src/claude-hoodie/\(source).webp")
    guard let image = NSImage(contentsOf: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot read \(path.path)") }
    // No resampling: retain original 640px height; add only transparent side margins.
    let x = ((side - cg.width) / 2)
    ctx.draw(cg, in: CGRect(x: x, y: 0, width: cg.width, height: cg.height))
    guard let aligned = ctx.makeImage() else { fatalError("Canvas failed") }
    try write(aligned, to: destination)
    if source == "idle" { try write(aligned, to: "header") }
    print("wrote \(destination).png")
}
