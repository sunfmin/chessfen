import ChessfenKit
import SwiftUI

extension Color {
    /// The palette is shared with the renderer, which states its colours the way SVG does.
    init?(svg text: String) {
        guard let colour = SVGPaint(text)?.cgColor else { return nil }
        self.init(cgColor: colour)
    }
}

/// The piece drawings, parsed once each.
///
/// Parsing twelve SVG strings costs little, but it costs it on every frame if nobody
/// remembers the result, and a board is redrawn on every tap.
enum PieceGlyphs {
    private static var cache: [Character: SVGDocument] = [:]

    static func document(for piece: Piece) -> SVGDocument? {
        if let known = cache[piece.glyph] { return known }
        guard let parsed = SVGDocument(glyph: piece.glyph) else { return nil }
        cache[piece.glyph] = parsed
        return parsed
    }

    /// Draws one piece to fill `box`. The drawings are 45 units square with y pointing
    /// down, which is what a `GraphicsContext` uses too, so nothing needs flipping.
    static func draw(_ piece: Piece, in box: CGRect, into context: inout GraphicsContext) {
        guard let document = document(for: piece) else { return }
        let scale = box.width / PiecePaths.unitSize
        let transform = CGAffineTransform(translationX: box.minX, y: box.minY)
            .scaledBy(x: scale, y: scale)

        for shape in document.shapes {
            let path = Path(shape.path).applying(transform)
            if let fill = shape.fill.cgColor {
                context.fill(
                    path,
                    with: .color(Color(cgColor: fill)),
                    style: FillStyle(eoFill: shape.usesEvenOddFill)
                )
            }
            if let stroke = shape.stroke.cgColor, shape.strokeWidth > 0 {
                context.stroke(
                    path,
                    with: .color(Color(cgColor: stroke)),
                    style: StrokeStyle(
                        lineWidth: shape.strokeWidth * scale,
                        lineCap: shape.lineCap,
                        lineJoin: shape.lineJoin
                    )
                )
            }
        }
    }
}

/// One piece on its own, for the editor's palette.
struct PieceGlyphView: View {
    let piece: Piece

    var body: some View {
        Canvas { context, size in
            PieceGlyphs.draw(
                piece, in: CGRect(origin: .zero, size: size), into: &context
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The board: two `Canvas` layers with the pieces between them.
///
/// The squares and the markers are drawn rather than composed, because a view per square
/// would be a hundred views changing on every tap. The pieces are the exception, and they
/// are the exception on purpose: each one is its own view so that SwiftUI can move it, which
/// is the whole difference between a move that travels and a board that cuts.
///
/// The paths and the palette are the renderer's, so what the player sees on screen and what
/// recognition was tested against are the same board.
struct BoardView: View {
    var pieces: [Square: Piece]
    var orientation: Orientation = .whiteAtBottom
    /// The move that led here: which squares to tint, and which piece travelled where.
    var lastMove: MoveSquares?
    /// Kings in check and whoever is checking them.
    var checks: Set<Square> = []
    /// Squares recognition was not sure about (docs/adr/0008).
    var suspects: Set<Square> = []
    var selected: Square?
    var destinations: Set<Square> = []
    var captures: Set<Square> = []
    /// The engine's current Best Move.
    var recommendation: MoveSquares?
    var coordinates = true
    var isInteractive = true
    var onTap: ((Square) -> Void)?
    /// The photograph this position was read from, laid under the pieces.
    var backdrop: Backdrop?

    /// A picture behind the pieces, and how much of itself it is allowed to be.
    ///
    /// It goes over the squares and under the pieces, which is the whole idea: the board it shows
    /// is the same eight by eight, so a piece read wrong shows up as two different things in one
    /// square and the eye never has to travel to find the disagreement.
    struct Backdrop {
        let image: Image
        /// How far the picture comes through the board.
        var opacity: Double
        /// Held down while comparing, so the photograph does not shout over the drawn pieces. At
        /// full strength the picture is the answer rather than a reference, and nothing is muted.
        var saturation: Double
        /// Whether the drawn pieces stay on top. Two boards at full strength on top of each other
        /// is neither of them, so the mode that shows the photograph outright hides them.
        var showsPieces: Bool
    }

    private let style = BoardStyle.default

    /// The two squares of the move just played, washed in the screen's green.
    ///
    /// Gold was tried and lost twice over: any gold near the wood either disappears into it or
    /// impersonates the other square colour, and an opaque one bright enough to survive erased
    /// the light/dark join it covered. Green is nowhere in the wood, so a thin wash of it is
    /// plainly a mark at any strength — and being a wash, the checker pattern goes on showing
    /// through it.
    private static var lastMoveWash: Color { Palette.analysis.opacity(0.42) }

    /// The pieces as things that persist, so that a move is one piece travelling rather
    /// than the whole board being redrawn (see TrackedPlacement).
    @State private var tracked = TrackedPlacement()

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // The squares and everything under the pieces.
                Canvas { context, size in drawGround(into: &context, size: size) }
                if let backdrop {
                    backdrop.image
                        .resizable()
                        .frame(width: side, height: side)
                        .saturation(backdrop.saturation)
                        .opacity(backdrop.opacity)
                        .allowsHitTesting(false)
                }
                pieceLayer(side: side)
                    .opacity(backdrop?.showsPieces == false ? 0 : 1)
                // Selection, destinations and the recommendation arrow go over the pieces,
                // because a ring around a piece about to be taken has to be visible.
                Canvas { context, size in drawMarkers(into: &context, size: size) }
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        guard isInteractive, let onTap,
                            let square = square(at: event.location, side: side)
                        else { return }
                        onTap(square)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("棋盘")
        .onAppear { tracked.settle(to: pieces) }
        .onChange(of: pieces) { _, placement in
            // Snappy rather than smooth: a move should land, not glide. Long enough to see
            // which piece went where, short enough that the next tap is never waiting on it.
            withAnimation(.snappy(duration: 0.18)) {
                tracked.update(to: placement, moved: lastMove)
            }
        }
    }

    private func pieceLayer(side: CGFloat) -> some View {
        let cell = side / 8
        return ZStack {
            ForEach(tracked.items) { item in
                let position = self.cell(of: item.square)
                PieceGlyphView(piece: item.piece)
                    .frame(width: cell, height: cell)
                    .position(
                        x: (CGFloat(position.column) + 0.5) * cell,
                        y: (CGFloat(position.row) + 0.5) * cell
                    )
                    // The piece that just moved passes over the one it captured, not under.
                    .zIndex(item.square == lastMove?.to ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    // ------------------------------------------------------------- geometry

    private func square(at point: CGPoint, side: CGFloat) -> Square? {
        guard side > 0 else { return nil }
        let cell = side / 8
        let column = Int(point.x / cell)
        let row = Int(point.y / cell)
        guard (0..<8).contains(column), (0..<8).contains(row) else { return nil }
        return Recognizer.square(row: row, column: column, orientation: orientation)
    }

    private func cell(of square: Square) -> (row: Int, column: Int) {
        switch orientation {
        case .whiteAtBottom: (row: 7 - square.rank, column: square.file)
        case .blackAtBottom: (row: square.rank, column: 7 - square.file)
        }
    }

    // -------------------------------------------------------------- drawing

    /// Everything under the pieces: the squares themselves, the last move's tint, a checked
    /// king's halo and the coordinates.
    private func drawGround(into context: inout GraphicsContext, size: CGSize) {
        let cell = min(size.width, size.height) / 8

        let light = Color(svg: style.lightSquare) ?? .white
        let dark = Color(svg: style.darkSquare) ?? .brown
        let moved = lastMove?.squares ?? []

        for row in 0..<8 {
            for column in 0..<8 {
                let square = Recognizer.square(row: row, column: column, orientation: orientation)
                let box = CGRect(
                    x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell
                )
                let isLight = (row + column).isMultiple(of: 2)
                context.fill(Path(box), with: .color(isLight ? light : dark))
                if moved.contains(square) {
                    context.fill(Path(box), with: .color(Self.lastMoveWash))
                }
                if checks.contains(square) { drawCheck(in: box, into: &context) }
                if coordinates {
                    drawCoordinate(row: row, column: column, in: box, into: &context)
                }
            }
        }
    }

    /// Everything over the pieces: what is selected, where it may go, what recognition was
    /// unsure of, and what the engine would play.
    ///
    /// Ink for the first two and teal for the last, which is the whole colour scheme of the app in
    /// one method: what you are doing is drawn in the board's own ink, and what the engine thinks
    /// is the only thing on screen allowed to be teal.
    private func drawMarkers(into context: inout GraphicsContext, size: CGSize) {
        let cell = min(size.width, size.height) / 8

        for row in 0..<8 {
            for column in 0..<8 {
                let square = Recognizer.square(row: row, column: column, orientation: orientation)
                let box = CGRect(
                    x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell
                )
                if suspects.contains(square) { drawSuspect(in: box, into: &context) }
                if selected == square {
                    context.stroke(
                        Path(box.insetBy(dx: cell * 0.04, dy: cell * 0.04)),
                        with: .color(Palette.ink.opacity(0.85)),
                        lineWidth: cell * 0.08
                    )
                }
                if destinations.contains(square) {
                    drawDestination(in: box, isCapture: captures.contains(square), into: &context)
                }
            }
        }

        if let recommendation { drawArrow(recommendation, cell: cell, into: &context) }
    }

    private func drawCheck(in box: CGRect, into context: inout GraphicsContext) {
        // The same idea as the renderer's halo: red at the king, fading out well before the
        // square's edge, so a checked king reads at a glance without hiding the piece.
        context.fill(
            Path(ellipseIn: box),
            with: .radialGradient(
                Gradient(colors: [
                    Color.red.opacity(0.9), Color.red.opacity(0.55), Color.red.opacity(0),
                ]),
                center: CGPoint(x: box.midX, y: box.midY),
                startRadius: 0,
                endRadius: box.width * 0.62
            )
        )
    }

    private func drawSuspect(in box: CGRect, into context: inout GraphicsContext) {
        context.stroke(
            Path(box.insetBy(dx: box.width * 0.05, dy: box.width * 0.05)),
            with: .color(.orange),
            style: StrokeStyle(lineWidth: box.width * 0.07, dash: [box.width * 0.14])
        )
    }

    private func drawDestination(
        in box: CGRect, isCapture: Bool, into context: inout GraphicsContext
    ) {
        if isCapture {
            // A ring around the piece being taken, so the piece stays visible.
            context.stroke(
                Path(ellipseIn: box.insetBy(dx: box.width * 0.06, dy: box.width * 0.06)),
                with: .color(Palette.ink.opacity(0.7)),
                lineWidth: box.width * 0.09
            )
        } else {
            let inset = box.width * 0.36
            context.fill(
                Path(ellipseIn: box.insetBy(dx: inset, dy: inset)),
                with: .color(Palette.ink.opacity(0.45))
            )
        }
    }

    private func drawArrow(
        _ move: MoveSquares, cell: CGFloat, into context: inout GraphicsContext
    ) {
        func centre(_ square: Square) -> CGPoint {
            let position = self.cell(of: square)
            return CGPoint(
                x: (CGFloat(position.column) + 0.5) * cell,
                y: (CGFloat(position.row) + 0.5) * cell
            )
        }
        let start = centre(move.from)
        let end = centre(move.to)
        let angle = atan2(end.y - start.y, end.x - start.x)
        // Wide enough to be read at a glance across a room, because that is what it is for: the one
        // mark on the board that is the engine talking, over artwork with strokes of its own. A
        // hairline arrow over a drawn knight is a scratch; this is a gesture.
        let head = cell * 0.46
        // Stop the shaft short of the point so the head is not drawn over itself.
        let tip = CGPoint(x: end.x - cos(angle) * cell * 0.06, y: end.y - sin(angle) * cell * 0.06)
        let base = CGPoint(x: tip.x - cos(angle) * head, y: tip.y - sin(angle) * head)

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: base)
        // Teal, because teal is the engine's voice everywhere else on the screen (Palette).
        let colour = Palette.analysis.opacity(0.78)
        context.stroke(
            shaft, with: .color(colour),
            style: StrokeStyle(lineWidth: cell * 0.18, lineCap: .round)
        )

        var arrowhead = Path()
        arrowhead.move(to: tip)
        arrowhead.addLine(
            to: CGPoint(
                x: base.x + cos(angle + .pi / 2) * head * 0.62,
                y: base.y + sin(angle + .pi / 2) * head * 0.62
            )
        )
        arrowhead.addLine(
            to: CGPoint(
                x: base.x + cos(angle - .pi / 2) * head * 0.62,
                y: base.y + sin(angle - .pi / 2) * head * 0.62
            )
        )
        arrowhead.closeSubpath()
        context.fill(arrowhead, with: .color(colour))
    }

    private func drawCoordinate(
        row: Int, column: Int, in box: CGRect, into context: inout GraphicsContext
    ) {
        // Inline, in the corner of the edge squares, rather than in a margin: the board
        // should use the whole width of a phone.
        let square = Recognizer.square(row: row, column: column, orientation: orientation)
        let isLight = (row + column).isMultiple(of: 2)
        // Held back to half strength: the coordinates share the first and last rank with pieces,
        // and at full contrast a rank number behind a rook reads as a mistake rather than as a
        // label. They only have to be findable when looked for.
        let ink =
            ((isLight ? Color(svg: style.darkSquare) : Color(svg: style.lightSquare)) ?? .gray)
            .opacity(0.5)
        let font = Font.system(size: box.width * 0.18, weight: .semibold)

        if row == 7 {
            let name = String(UnicodeScalar(UInt8(97 + square.file)))
            context.draw(
                Text(name).font(font).foregroundStyle(ink),
                at: CGPoint(x: box.maxX - box.width * 0.12, y: box.maxY - box.width * 0.1),
                anchor: .bottomTrailing
            )
        }
        if column == 0 {
            context.draw(
                Text("\(square.rank + 1)").font(font).foregroundStyle(ink),
                at: CGPoint(x: box.minX + box.width * 0.1, y: box.minY + box.width * 0.08),
                anchor: .topLeading
            )
        }
    }
}
