/// What was found on a square, and how sure the matcher is.
public struct SquareVerdict: Hashable, Sendable {
    public let piece: Piece?
    /// Silhouette IoU with the winning Template, or Ink coverage for an empty square.
    public let score: Double
    /// Gap to the runner-up Template; 1 when the square is empty.
    public let margin: Double

    /// False for a Shaky Square — the ones the Confirm Position screen points at.
    public var confident: Bool {
        guard piece != nil else { return true }
        return score >= SquareClassifier.lowScore && margin >= SquareClassifier.lowMargin
    }
}

public enum SquareClassifier {
    /// Above this brightness the piece body is white, below it black.
    static let whiteLuma = 128.0
    /// Shape agreement below this is shaky.
    public static let lowScore = 0.55
    /// A gap to the runner-up below this is shaky.
    public static let lowMargin = 0.04

    /// Matches the square's Ink against the piece Silhouettes of its own colour.
    ///
    /// Only its own colour: telling a white knight from a black knight is a question about
    /// brightness, which the body luma already answered, and mixing the two sides into one
    /// twelve-way shape contest would only invite a white bishop to win as a black one.
    public static func classify(_ reading: SquareReading) -> SquareVerdict {
        guard reading.occupied else {
            return SquareVerdict(piece: nil, score: reading.coverage, margin: 1)
        }
        let colour: PieceColour = (reading.bodyLuma ?? 0) >= whiteLuma ? .white : .black
        let shape = Morphology.normalise(reading.ink, size: PieceTemplates.shapeSize)

        // A Silhouette is scored against the Template and against its mirror, because a
        // photographed board can be seen from either side and half the pieces are not
        // symmetric — a knight faces left or right depending on which way you look.
        var scored: [(score: Double, kind: PieceKind)] = PieceTemplates.shapes(for: colour)
            .map { kind, template in
                let upright = Morphology.intersectionOverUnion(shape, template)
                let mirrored = Morphology.intersectionOverUnion(shape, template.mirrored)
                return (max(upright, mirrored), kind)
            }
        scored.sort { $0.score > $1.score }
        guard let best = scored.first else {
            return SquareVerdict(piece: nil, score: reading.coverage, margin: 1)
        }
        let runnerUp = scored.count > 1 ? scored[1].score : 0
        return SquareVerdict(
            piece: Piece(colour: colour, kind: best.kind),
            score: best.score,
            margin: best.score - runnerUp
        )
    }
}
