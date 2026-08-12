import ChessfenKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Testing

/// A board photographed from an angle is a projection of the board plus whatever the table
/// contributes. These tests build that on purpose: warp a rendered board onto a page, then
/// ask for the FEN back.

/// Paints `image` onto a `width`-by-`height` page, projected onto `quad`.
private func photographed(
    _ image: RGBImage,
    onto quad: BoardQuad,
    width: Int,
    height: Int,
    page: (Double, Double, Double) = (150, 148, 143)
) throws -> RGBImage {
    let source = try #require(image.cgImage)
    let pageHeight = Double(height)
    func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: pageHeight - point.y) }

    let transform = CIFilter.perspectiveTransform()
    transform.inputImage = CIImage(cgImage: source)
    transform.topLeft = flipped(quad.topLeft)
    transform.topRight = flipped(quad.topRight)
    transform.bottomRight = flipped(quad.bottomRight)
    transform.bottomLeft = flipped(quad.bottomLeft)
    let warped = try #require(transform.outputImage)

    let background = CIImage(
        color: CIColor(red: page.0 / 255, green: page.1 / 255, blue: page.2 / 255)
    )
    .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    let composed = warped.composited(over: background)
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

    let context = CIContext()
    let rendered = try #require(
        context.createCGImage(composed, from: CGRect(x: 0, y: 0, width: width, height: height))
    )
    return try #require(RGBImage(cgImage: rendered))
}

@Test("a board photographed from an angle is straightened and read")
func aSkewedBoardIsRectified() async throws {
    let fen = "r3k3/2N5/8/8/8/8/8/4K3 w - - 0 1"
    let board = try #require(BoardRenderer.image(fen: fen, options: .init(size: 640)))
    // Looking down at the board from above and to the left: the far edge is shorter and
    // the whole thing leans.
    let quad = BoardQuad(
        topLeft: CGPoint(x: 210, y: 120),
        topRight: CGPoint(x: 690, y: 175),
        bottomRight: CGPoint(x: 745, y: 690),
        bottomLeft: CGPoint(x: 130, y: 640)
    )
    let photo = try photographed(board, onto: quad, width: 900, height: 820)

    let result = try await Recognizer.recognise(
        photograph: photo, orientation: .whiteAtBottom, castling: .none
    )
    #expect(result.fen == fen)
}

@Test("a straight screenshot is read without being warped")
func aStraightPictureIsLeftAlone() async throws {
    let screenshot = try referenceScreenshot()
    let through = try await Recognizer.recognise(
        photograph: screenshot, turn: .black, castling: .none
    )
    let direct = try Recognizer.recognise(screenshot, turn: .black, castling: .none)
    #expect(through.fen == direct.fen)
    #expect(through.rect == direct.rect)
    #expect(through.image.width == direct.image.width)
    #expect(through.checkerScore >= Recognizer.alreadyStraightScore)
}

@Test("the quad refinement walks a loose rectangle onto the board")
func refinementFindsTheBoardEdges() throws {
    let fen = PGN.standardStartFEN
    let board = try #require(BoardRenderer.image(fen: fen, options: .init(size: 480)))
    let quad = BoardQuad(
        topLeft: CGPoint(x: 100, y: 60),
        topRight: CGPoint(x: 580, y: 110),
        bottomRight: CGPoint(x: 620, y: 570),
        bottomLeft: CGPoint(x: 70, y: 540)
    )
    let photo = try photographed(board, onto: quad, width: 700, height: 660)

    // Deliberately loose: every corner is thirty pixels out.
    var loose = quad
    loose.corners = [
        CGPoint(x: 70, y: 30), CGPoint(x: 610, y: 80),
        CGPoint(x: 650, y: 600), CGPoint(x: 40, y: 570),
    ]
    let before = PerspectiveCorrection.score(loose, in: photo)
    let after = PerspectiveCorrection.refined(loose, in: photo)
    #expect(after.score > before)

    // The claim is about the corners: the descent's job is to find the board's edges, and
    // whether the pieces on it then read is the rest of the pipeline's business.
    for (found, truth) in zip(after.quad.corners, quad.corners) {
        let distance = (
            (found.x - truth.x) * (found.x - truth.x)
            + (found.y - truth.y) * (found.y - truth.y)
        ).squareRoot()
        #expect(distance < 8, "corner \(found) should be near \(truth)")
    }
}

@Test("a quad that has folded over itself is refused rather than scored")
func implausibleQuadsAreRefused() {
    let inside = BoardQuad(rect: CGRect(x: 10, y: 10, width: 200, height: 200))
    #expect(inside.isPlausible(in: 300, height: 300))

    // Corners swapped left for right, so the quad crosses itself.
    var crossed = inside
    crossed.corners = [
        CGPoint(x: 210, y: 10), CGPoint(x: 10, y: 10),
        CGPoint(x: 210, y: 210), CGPoint(x: 10, y: 210),
    ]
    #expect(!crossed.isPlausible(in: 300, height: 300))

    // Too small to hold eight squares.
    let tiny = BoardQuad(rect: CGRect(x: 0, y: 0, width: 40, height: 40))
    #expect(!tiny.isPlausible(in: 300, height: 300))

    // Well outside the picture.
    let escaped = BoardQuad(rect: CGRect(x: -400, y: 0, width: 200, height: 200))
    #expect(!escaped.isPlausible(in: 300, height: 300))
}

@Test("a photograph with no board in it is still rejected")
func aPhotographWithNoBoardIsRejected() async throws {
    var pixels = [UInt8](repeating: 190, count: 400 * 400 * 3)
    for y in 150..<250 {
        for x in 120..<300 {
            let base = (y * 400 + x) * 3
            pixels[base] = 60
            pixels[base + 1] = 70
            pixels[base + 2] = 90
        }
    }
    let noise = RGBImage(width: 400, height: 400, pixels: pixels)
    await #expect(throws: RecognitionError.boardNotFound) {
        try await Recognizer.recognise(photograph: noise)
    }
}
