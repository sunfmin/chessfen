import CoreGraphics
import Foundation
import ImageIO

/// The pixels of a picture, three bytes to a pixel. Alpha is flattened onto white on the
/// way in, because a transparent screenshot of a board is a board on a white page.
public struct RGBImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major, three bytes per pixel.
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inline(__always)
    public func red(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 3] }
    @inline(__always)
    public func green(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 3 + 1] }
    @inline(__always)
    public func blue(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 3 + 2] }

    @inline(__always)
    public func channels(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        let base = (y * width + x) * 3
        return (Double(pixels[base]), Double(pixels[base + 1]), Double(pixels[base + 2]))
    }

    public func cropped(x: Int, y: Int, width cropWidth: Int, height cropHeight: Int) -> RGBImage {
        let left = max(0, x)
        let top = max(0, y)
        let right = min(width, x + cropWidth)
        let bottom = min(height, y + cropHeight)
        guard right > left, bottom > top else { return RGBImage(width: 0, height: 0, pixels: []) }

        var out = [UInt8]()
        out.reserveCapacity((right - left) * (bottom - top) * 3)
        for row in top..<bottom {
            let start = (row * width + left) * 3
            let end = (row * width + right) * 3
            out.append(contentsOf: pixels[start..<end])
        }
        return RGBImage(width: right - left, height: bottom - top, pixels: out)
    }

    /// ITU-R BT.601 luma, the same weights PIL's "L" mode uses.
    public var luma: LumaImage {
        var out = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 3
            out[index] =
                0.299 * Double(pixels[base])
                + 0.587 * Double(pixels[base + 1])
                + 0.114 * Double(pixels[base + 2])
        }
        return LumaImage(width: width, height: height, values: out)
    }
}

// -------------------------------------------------------------------- loading

extension RGBImage {
    public init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        // Premultiplied-onto-white happens by painting the canvas first.
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = rgba.withUnsafeMutableBytes({ bytes in
            CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colourSpace,
                bitmapInfo: info
            )
        }) else { return nil }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            out[index * 3] = bytes[index * 4]
            out[index * 3 + 1] = bytes[index * 4 + 1]
            out[index * 3 + 2] = bytes[index * 4 + 2]
        }
        self.init(width: width, height: height, pixels: out)
    }

    public init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(cgImage: image)
    }

    public init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(cgImage: image)
    }

    public var cgImage: CGImage? {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            rgba[index * 4] = pixels[index * 3]
            rgba[index * 4 + 1] = pixels[index * 3 + 1]
            rgba[index * 4 + 2] = pixels[index * 3 + 2]
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// The same picture with its longer side at most `longestSide`, or itself if it
    /// already is. Never enlarges.
    public func scaled(toLongestSide longestSide: Int) -> RGBImage {
        let longer = max(width, height)
        guard longer > longestSide, longestSide > 0 else { return self }
        let scale = Double(longestSide) / Double(longer)
        return resized(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }

    /// The picture stretched to exactly this size, aspect ratio be damned — which is what
    /// a rectified board wants, a board being square whatever the camera made of it.
    public func resized(width newWidth: Int, height newHeight: Int) -> RGBImage {
        guard newWidth > 0, newHeight > 0 else { return self }
        guard newWidth != width || newHeight != height else { return self }
        guard let source = cgImage else { return self }

        var rgba = [UInt8](repeating: 255, count: newWidth * newHeight * 4)
        let context = rgba.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: newWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        }
        guard let context else { return self }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let data = context.data else { return self }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: newWidth * newHeight * 3)
        for index in 0..<(newWidth * newHeight) {
            out[index * 3] = bytes[index * 4]
            out[index * 3 + 1] = bytes[index * 4 + 1]
            out[index * 3 + 2] = bytes[index * 4 + 2]
        }
        return RGBImage(width: newWidth, height: newHeight, pixels: out)
    }
}

// ----------------------------------------------------------------- morphology

/// Binary morphology and shape measures, hand-rolled for the same reason the Python
/// version hand-rolled them: a square is about a hundred pixels across, so a dependency
/// would be bought for nothing. Structuring elements are squares, zero-padded at the edge.
public enum Morphology {
    public static func erode(_ mask: Mask, radius: Int) -> Mask {
        guard radius > 0 else { return mask }
        var out = mask
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                guard mask[x, y] else { continue }
                var keep = true
                search: for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if !mask.contains(x: nx, y: ny) || !mask[nx, ny] {
                            keep = false
                            break search
                        }
                    }
                }
                out[x, y] = keep
            }
        }
        return out
    }

    public static func dilate(_ mask: Mask, radius: Int) -> Mask {
        guard radius > 0 else { return mask }
        var out = mask
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                guard !mask[x, y] else { continue }
                var grow = false
                search: for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if mask.contains(x: nx, y: ny), mask[nx, ny] {
                            grow = true
                            break search
                        }
                    }
                }
                out[x, y] = grow
            }
        }
        return out
    }

    /// Bridges hairline gaps without growing the shape.
    public static func close(_ mask: Mask, radius: Int) -> Mask {
        erode(dilate(mask, radius: radius), radius: radius)
    }

    /// Four-connected components of at least `minimumArea` pixels.
    public static func components(_ mask: Mask, minimumArea: Int) -> [Mask] {
        var remaining = mask
        var found: [Mask] = []
        var stack: [(Int, Int)] = []

        for startY in 0..<mask.height {
            for startX in 0..<mask.width where remaining[startX, startY] {
                var blob = Mask(width: mask.width, height: mask.height, repeating: false)
                var area = 0
                stack.append((startX, startY))
                while let (x, y) = stack.popLast() {
                    guard remaining[x, y] else { continue }
                    remaining[x, y] = false
                    blob[x, y] = true
                    area += 1
                    if y > 0 { stack.append((x, y - 1)) }
                    if y + 1 < mask.height { stack.append((x, y + 1)) }
                    if x > 0 { stack.append((x - 1, y)) }
                    if x + 1 < mask.width { stack.append((x + 1, y)) }
                }
                if area >= minimumArea { found.append(blob) }
            }
        }
        return found
    }

    /// Closes interior holes, so a piece drawn as a hollow outline becomes a Silhouette.
    ///
    /// Needed whenever a piece's fill happens to match its square — a white piece on a
    /// nearly white square, where only the outline registers as Ink. An outline ring must
    /// not be matched against filled Templates.
    public static func fillHoles(_ mask: Mask) -> Mask {
        var filled = mask
        let background = mask.map { !$0 }
        for blob in components(background, minimumArea: 1) {
            var touchesBorder = false
            check: for y in 0..<blob.height {
                for x in 0..<blob.width where blob[x, y] {
                    if x == 0 || y == 0 || x == blob.width - 1 || y == blob.height - 1 {
                        touchesBorder = true
                        break check
                    }
                }
            }
            guard !touchesBorder else { continue }
            filled.formUnion(blob)
        }
        return filled
    }

    /// Crops to the ink, scales to fit a `size` box keeping aspect ratio, and centres it.
    ///
    /// Letterboxing rather than stretching is deliberate: aspect ratio is what separates a
    /// pawn from a king, so it has to survive normalisation.
    public static func normalise(_ mask: Mask, size: Int) -> Mask {
        var minX = mask.width, minY = mask.height, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask[x, y] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return Mask(width: size, height: size, repeating: false)
        }

        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        let scale = Double(size) / Double(max(cropWidth, cropHeight))
        let targetWidth = max(1, Int((Double(cropWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(cropHeight) * scale).rounded()))

        // Area-average resampling, which is what a bilinear downscale of a binary mask
        // amounts to: a target pixel is set when the source region it covers is mostly set.
        var canvas = Mask(width: size, height: size, repeating: false)
        let left = (size - targetWidth) / 2
        let top = (size - targetHeight) / 2
        for ty in 0..<targetHeight {
            let y0 = minY + Int((Double(ty) / Double(targetHeight) * Double(cropHeight)).rounded(.down))
            let y1 = minY + max(y0 - minY + 1, Int((Double(ty + 1) / Double(targetHeight) * Double(cropHeight)).rounded(.down)))
            for tx in 0..<targetWidth {
                let x0 = minX + Int((Double(tx) / Double(targetWidth) * Double(cropWidth)).rounded(.down))
                let x1 = minX + max(x0 - minX + 1, Int((Double(tx + 1) / Double(targetWidth) * Double(cropWidth)).rounded(.down)))
                var set = 0, total = 0
                for y in y0..<min(y1, mask.height) {
                    for x in x0..<min(x1, mask.width) {
                        total += 1
                        if mask[x, y] { set += 1 }
                    }
                }
                if total > 0, Double(set) / Double(total) > 0.5 {
                    canvas[left + tx, top + ty] = true
                }
            }
        }
        return canvas
    }

    /// Intersection over union of two equally shaped masks.
    public static func intersectionOverUnion(_ left: Mask, _ right: Mask) -> Double {
        precondition(left.width == right.width && left.height == right.height)
        var intersection = 0
        var union = 0
        for index in left.values.indices {
            let a = left.values[index], b = right.values[index]
            if a || b { union += 1 }
            if a && b { intersection += 1 }
        }
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}
