import ChessfenKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

/// Screenshots in the wild are recompressed, rescaled and pasted onto pages.

private let expected = "r3k3/2N5/8/8/8/8/8/8 w - - 0 1"

/// Re-encodes as JPEG at `quality` and decodes what comes back — the artefacts are the
/// point, so the round trip through the codec has to be real.
private func recompressed(_ image: RGBImage, quality: Double) throws -> RGBImage {
    let source = try #require(image.cgImage)
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(
            data as CFMutableData, "public.jpeg" as CFString, 1, nil
        )
    )
    CGImageDestinationAddImage(
        destination, source,
        [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    )
    #expect(CGImageDestinationFinalize(destination))
    return try #require(RGBImage(data: data as Data))
}

private func rescaled(_ image: RGBImage, by scale: Double) -> RGBImage {
    image.scaled(toLongestSide: Int((Double(max(image.width, image.height)) * scale).rounded()))
}

@Test("JPEG artefacts are tolerated", arguments: [0.85, 0.55, 0.30])
func jpegArtefactsAreTolerated(quality: Double) throws {
    let image = try recompressed(referenceScreenshot(), quality: quality)
    let result = try Recognizer.recognise(image, castling: .none)
    #expect(result.fen == expected)
}

@Test("small renderings are tolerated", arguments: [0.5, 0.35])
func smallRenderingsAreTolerated(scale: Double) throws {
    let image = rescaled(try referenceScreenshot(), by: scale)
    let result = try Recognizer.recognise(image, castling: .none)
    #expect(result.fen == expected)
}

@Test("below about thirty pixel squares it says so rather than inventing pieces")
func tinySquaresAreAdmitted() throws {
    // Shape matching against another piece set needs roughly 35 px squares. Past that the
    // answer degrades, and the point of the confidence numbers is to admit it.
    let image = rescaled(try referenceScreenshot(), by: 0.25)
    let result = try Recognizer.recognise(image, castling: .none)
    #expect(result.fen != expected)
    #expect(!result.shaky.isEmpty)
}

@Test("a board pasted off centre onto a page is still found")
func boardPastedOntoAPageIsFound() throws {
    let screenshot = try referenceScreenshot()
    var pixels = [UInt8](repeating: 0, count: 1100 * 950 * 3)
    for index in 0..<(1100 * 950) {
        pixels[index * 3] = 245
        pixels[index * 3 + 1] = 245
        pixels[index * 3 + 2] = 247
    }
    for y in 0..<screenshot.height {
        for x in 0..<screenshot.width {
            let (red, green, blue) = screenshot.channels(x, y)
            let base = ((y + 120) * 1100 + x + 60) * 3
            pixels[base] = UInt8(red)
            pixels[base + 1] = UInt8(green)
            pixels[base + 2] = UInt8(blue)
        }
    }
    let page = RGBImage(width: 1100, height: 950, pixels: pixels)

    let result = try Recognizer.recognise(page, castling: .none)
    #expect(result.fen == expected)
    // The screenshot carries ~15 px of its own padding, which the search sees through.
    #expect(abs(result.rect.left - 75) <= 4, "left was \(result.rect.left)")
    #expect(abs(result.rect.top - 129) <= 4, "top was \(result.rect.top)")
}
