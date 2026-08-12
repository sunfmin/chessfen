/// One principal variation: the moves the engine expects and the Score they lead to.
public struct Line: Hashable, Sendable {
    /// White-relative, like every Score in this package.
    public let score: Score
    /// UCI moves from the analysed Position onwards. Never empty for a real Line.
    public let uciMoves: [String]
    /// The same moves in SAN, for showing to a player.
    public let san: [String]

    public var bestMove: String? { uciMoves.first }
}

/// What the engine reports about a Position at one Depth.
///
/// A snapshot, never a verdict: an Analysis runs unbounded, so a later one at a greater
/// Depth may say something different, and often does. The UI is expected to replace what
/// it is showing each time one of these arrives.
public struct Analysis: Hashable, Sendable {
    public let depth: Int
    /// How far the search looked down the most forcing lines.
    public let selectiveDepth: Int
    /// Best first. As many as `multiPV` asked for, when the position has that many moves.
    public let lines: [Line]
    public let nodes: UInt64
    public let nodesPerSecond: UInt64
    public let timeMilliseconds: UInt64
    /// Fraction of the transposition table in use, per mille.
    public let hashFull: Int
    /// True when the Depth's search was cut off before its Score was proven, so the
    /// numbers are bounds rather than values. Worth showing, worth not trusting.
    public let isPartial: Bool

    public var best: Line? { lines.first }
    public var bestMove: String? { best?.bestMove }
}
