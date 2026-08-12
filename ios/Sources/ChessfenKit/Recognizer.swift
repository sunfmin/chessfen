/// Which side is at the bottom of the picture.
public enum Orientation: String, Hashable, Sendable, CaseIterable {
    case whiteAtBottom = "white"
    case blackAtBottom = "black"
}

/// How to fill in the castling field, which a picture cannot actually show.
public enum CastlingGuess: String, Hashable, Sendable, CaseIterable {
    /// Grant rights wherever a king and rook still sit on their home squares.
    case fromHomeSquares = "auto"
    case none = "none"
}

/// The recognised Position plus the evidence behind it.
public struct Recognition: Sendable {
    public let fen: String
    public let rect: BoardRect
    public let orientation: Orientation
    public let verdicts: [Square: SquareVerdict]

    /// The Shaky Squares, in board order — the ones worth a human glance.
    public var shaky: [(square: Square, verdict: SquareVerdict)] {
        verdicts
            .filter { !$0.value.confident }
            .sorted { $0.key.index < $1.key.index }
            .map { (square: $0.key, verdict: $0.value) }
    }

    public func piece(at square: Square) -> Piece? { verdicts[square]?.piece }
}

public enum Recognizer {
    /// Longest side the search runs at. A phone camera hands over twelve megapixels of a
    /// board that needs a few hundred pixels a square to be read; the rest is search cost
    /// and JPEG noise. Boards arriving as screenshots are smaller than this and untouched.
    public static let workingResolution = 1200

    /// Recognises the Position in a board image.
    ///
    /// `turn`, `orientation` and `castling` are Unknowable Fields as far as the picture is
    /// concerned: nothing in it can settle whose move it is. They are answered here so
    /// that the result is a complete FEN, and re-answered by the player at the Confirm
    /// Position screen.
    public static func recognise(
        _ source: RGBImage,
        turn: PieceColour = .white,
        orientation requested: Orientation? = nil,
        castling: CastlingGuess = .fromHomeSquares
    ) throws -> Recognition {
        let image = source.scaled(toLongestSide: workingResolution)
        let rect = try BoardGeometry.findBoard(in: image)

        var grid: [[SquareVerdict]] = []
        for row in 0..<8 {
            var line: [SquareVerdict] = []
            for column in 0..<8 {
                let cell = rect.crop(image, row: row, column: column)
                line.append(SquareClassifier.classify(SquareReader.read(cell)))
            }
            grid.append(line)
        }

        let orientation = requested ?? inferOrientation(grid)
        var verdicts: [Square: SquareVerdict] = [:]
        for row in 0..<8 {
            for column in 0..<8 {
                verdicts[square(row: row, column: column, orientation: orientation)] =
                    grid[row][column]
            }
        }
        return Recognition(
            fen: fen(verdicts, turn: turn, castling: castling),
            rect: rect,
            orientation: orientation,
            verdicts: verdicts
        )
    }

    /// Maps a grid Cell (row 0 = top of the picture) to a board square.
    public static func square(row: Int, column: Int, orientation: Orientation) -> Square {
        switch orientation {
        case .whiteAtBottom: Square(file: column, rank: 7 - row)
        case .blackAtBottom: Square(file: 7 - column, rank: row)
        }
    }

    /// Guesses which side is at the bottom from where each colour's pieces sit.
    ///
    /// A flip is a point reflection, so it preserves every rule of chess — no legality
    /// check can tell the two readings apart. What does lean one way is that armies
    /// advance from their own side: the colour whose pieces sit lower in the picture is
    /// almost always the colour playing up the board. Ties go to white at the bottom, by
    /// far the common case, and the player can say otherwise at the Confirm Position
    /// screen.
    static func inferOrientation(_ grid: [[SquareVerdict]]) -> Orientation {
        var whiteRows: [Int] = [], blackRows: [Int] = []
        for row in 0..<8 {
            for column in 0..<8 {
                guard let piece = grid[row][column].piece else { continue }
                if piece.colour == .white {
                    whiteRows.append(row)
                } else {
                    blackRows.append(row)
                }
            }
        }
        guard !whiteRows.isEmpty, !blackRows.isEmpty else { return .whiteAtBottom }
        let whiteDepth = Double(whiteRows.reduce(0, +)) / Double(whiteRows.count)
        let blackDepth = Double(blackRows.reduce(0, +)) / Double(blackRows.count)
        return whiteDepth >= blackDepth ? .whiteAtBottom : .blackAtBottom
    }

    /// Assembles a FEN from the 64 verdicts.
    ///
    /// The clocks are reset rather than guessed: a picture shows no history, and pretending
    /// otherwise would put a fifty-move draw in reach of a position that never played a
    /// move.
    static func fen(
        _ verdicts: [Square: SquareVerdict],
        turn: PieceColour,
        castling: CastlingGuess
    ) -> String {
        var placement: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var line = ""
            var empties = 0
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                if let piece = verdicts[square]?.piece {
                    if empties > 0 {
                        line += "\(empties)"
                        empties = 0
                    }
                    line.append(piece.glyph)
                } else {
                    empties += 1
                }
            }
            if empties > 0 { line += "\(empties)" }
            placement.append(line)
        }
        let rights = castlingField(verdicts, castling)
        return "\(placement.joined(separator: "/")) \(turn == .white ? "w" : "b") \(rights) - 0 1"
    }

    private static func castlingField(
        _ verdicts: [Square: SquareVerdict], _ castling: CastlingGuess
    ) -> String {
        guard castling == .fromHomeSquares else { return "-" }
        let rights: [(flag: Character, king: String, rook: String, colour: PieceColour)] = [
            ("K", "e1", "h1", .white), ("Q", "e1", "a1", .white),
            ("k", "e8", "h8", .black), ("q", "e8", "a8", .black),
        ]
        let granted = rights.filter { right in
            guard let kingSquare = Square(right.king), let rookSquare = Square(right.rook)
            else { return false }
            return verdicts[kingSquare]?.piece == Piece(colour: right.colour, kind: .king)
                && verdicts[rookSquare]?.piece == Piece(colour: right.colour, kind: .rook)
        }
        return granted.isEmpty ? "-" : String(granted.map(\.flag))
    }
}
