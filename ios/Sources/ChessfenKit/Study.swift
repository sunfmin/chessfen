/// A move offered at a past Ply and not yet committed.
///
/// Held rather than played, because a Drill is a question and a played move is an answer already
/// marked. Between the two there has to be a moment where the move is on the board, visible, and
/// still yours to take back — that moment is this (docs/adr/0015).
public struct Guess: Hashable, Sendable {
    /// Which Ply is being answered, counting from one: the move that was played from the
    /// position on screen.
    public let ply: Int
    public let move: Move
    public let san: String
}

/// What committing a Guess showed: your move, the engine's, and the one actually played, each
/// with a Score, all three computed at one Depth.
///
/// Three answers side by side and no combined number, because "you found the move" and "you found
/// a move as good as the engine's" and "you found what you played last time" are different facts,
/// and rolling them into a percentage is how an app ends up saying nothing.
public struct Reveal: Hashable, Sendable {
    public let ply: Int
    /// Whose move it was — the side the Scores below are read from the point of view of.
    public let mover: PieceColour
    /// The one Depth all three Scores were computed at. Without it they cannot be compared with
    /// each other, which is the whole lesson of docs/adr/0016.
    public let depth: Int

    public let guess: String
    public let guessScore: Score?
    /// The move that was played in the Game when it was played for real.
    public let played: String
    public let playedScore: Score?
    /// What the engine would play here. Nil when the engine could not be asked.
    public let best: String?
    public let bestScore: Score?

    public var isSameAsPlayed: Bool { guess == played }
    public var isSameAsBest: Bool { best.map { $0 == guess } ?? false }

    /// What the Guess gave up against the engine's move, in centipawns from the mover's point of
    /// view. Nil when either Score is missing.
    public var lost: Int? {
        guard let bestScore, let guessScore else { return nil }
        let swing = MoveQuality.centipawns(bestScore) - MoveQuality.centipawns(guessScore)
        return swing * (mover == .white ? 1 : -1)
    }

    /// How the Guess reads on the absolute scale — the same one a Review uses on a played move,
    /// so a Drill and a Review cannot disagree about what counts as a mistake.
    public var quality: MoveQuality? {
        MoveQuality.of(move: mover, before: bestScore, after: guessScore)
    }

    /// Whether the Guess is inside the band that counts: within half a pawn of the engine's move.
    ///
    /// The band is `MoveQuality`'s own — anything it calls 正常 counts — rather than a second
    /// threshold invented here. A Drill that graded on a stricter scale than the Review would be
    /// telling a player their move was wrong and the file that it was fine.
    public var counts: Bool? {
        quality.map { $0 == .fine }
    }
}

/// A uniform-depth pass over a Game, while it is running.
///
/// Every ply re-scored at one Depth so the Scores can be compared with each other. It is started
/// by turning the engine's opinion on and by nothing else — there is nowhere else to ask for it,
/// which is what makes the switch the only moment a Game can acquire one (docs/adr/0015, 0016).
public struct ReviewPass: Hashable, Sendable {
    public let depth: Int
    public var completed: Int
    public let total: Int
    public var isRunning: Bool

    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}
