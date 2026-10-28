import CoreGraphics
import Foundation

/// Keep the character plus nearby detached details, reject distant tile spill.
enum SpriteComponentCleanup {
    struct Result { let image: CGImage; let removedPixels: Int }
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    static func image(_ bytes: inout [UInt8], width: Int, height: Int) -> CGImage {
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            return ctx.makeImage()!
        }
    }
    static func clean(_ source: CGImage, detailRadius: Int = 8) -> Result {
        let w = source.width, h = source.height
        var bytes = rgba(source), visited = [Bool](repeating: false, count: w * h)
        var parts: [[Int]] = []
        for start in 0..<(w * h) where !visited[start] && bytes[start * 4 + 3] > 26 {
            var queue = [start], head = 0
            visited[start] = true
            while head < queue.count {
                let pixel = queue[head]; head += 1
                let x = pixel % w, y = pixel / w
                for yy in max(0, y - 1)...min(h - 1, y + 1) {
                    for xx in max(0, x - 1)...min(w - 1, x + 1) {
                        let next = yy * w + xx
                        if !visited[next] && bytes[next * 4 + 3] > 26 { visited[next] = true; queue.append(next) }
                    }
                }
            }
            parts.append(queue)
        }
        guard let largest = parts.max(by: { $0.count < $1.count }) else { return Result(image: source, removedPixels: 0) }
        var main = [Bool](repeating: false, count: w * h)
        for p in largest { main[p] = true }
        var keep = main
        for part in parts where part.count != largest.count {
            let close = detailRadius > 0 && part.contains { p in
                let x = p % w, y = p / w
                for yy in max(0, y - detailRadius)...min(h - 1, y + detailRadius) {
                    for xx in max(0, x - detailRadius)...min(w - 1, x + detailRadius) where main[yy * w + xx] { return true }
                }
                return false
            }
            if close { for p in part { keep[p] = true } }
        }
        // Preserve antialiasing within two pixels of retained visible components.
        var padded = keep
        for p in 0..<(w * h) where keep[p] {
            let x = p % w, y = p / w
            for yy in max(0, y - 2)...min(h - 1, y + 2) {
                for xx in max(0, x - 2)...min(w - 1, x + 2) { padded[yy * w + xx] = true }
            }
        }
        var removed = 0
        for p in 0..<(w * h) where !padded[p] && bytes[p * 4 + 3] != 0 {
            for channel in 0..<4 { bytes[p * 4 + channel] = 0 }
            removed += 1
        }
        return Result(image: image(&bytes, width: w, height: h), removedPixels: removed)
    }
}
