/// A Game: where it started and what has been played. Everything else — the current
/// Position, whose turn it is, what is legal, whether it is over — is derived from those
/// two facts on demand, so undo is dropping an element and a variation is a slice
/// (docs/adr/0003).
public struct Game: Hashable, Sendable {
    /// One move as played, kept with the SAN it was written as. SAN is stored rather than
    /// recomputed because it depends on the position the move was made in, and that
    /// position is gone once the move is played.
    public struct Ply: Hashable, Sendable {
        public let uci: String
        public let san: String
        /// White-relative score after this move, filled in by a Review.
        public var evaluation: Score?
        /// The moves that were played from this ply's own starting position instead of this
        /// ply — each one an alternative to *this* move and everything that followed it.
        ///
        /// A Variation is how a line that was tried and left behind stops being lost. Step
        /// back to move ten, play something else, and the eleven moves that used to be there
        /// move in here rather than into the bin; PGN has written them in brackets since 1994
        /// and this is the same thing.
        public var variations: [[Ply]] = []

        public init(
            uci: String, san: String, evaluation: Score? = nil, variations: [[Ply]] = []
        ) {
            self.uci = uci
            self.san = san
            self.evaluation = evaluation
            self.variations = variations
        }
    }

    public let startFEN: String
    public private(set) var plies: [Ply]
    /// The position after every ply, recomputed whenever the Game changes.
    public private(set) var state: GameState

    /// Fails when the FEN would not survive validation — the Confirm Position gate is
    /// what stops that from happening (docs/adr/0008).
    public init?(startFEN: String) {
        guard let state = Rules.probe(startFEN: startFEN) else { return nil }
        self.startFEN = startFEN
        self.plies = []
        self.state = state
    }

    /// Rebuilds a Game from a starting FEN and a list of UCI moves, refusing the lot if
    /// any move is not legal where it falls.
    public init?(startFEN: String, uciMoves: [String]) {
        guard var game = Game(startFEN: startFEN) else { return nil }
        for uci in uciMoves {
            guard game.apply(uci: uci) else { return nil }
        }
        self = game
    }

    public var isOver: Bool { state.outcome.isOver }

    /// Every position the Game has stood in, as UCI move prefixes — what a Review walks.
    public var uciMoves: [String] { plies.map(\.uci) }

    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        guard state.legalMoves.contains(move) else { return false }
        let san = SAN.text(for: move, in: state)
        guard let next = Rules.probe(startFEN: startFEN, moves: uciMoves + [move.uci])
        else { return false }
        plies.append(Ply(uci: move.uci, san: san))
        state = next
        return true
    }

    @discardableResult
    public mutating func apply(uci: String) -> Bool {
        guard let move = state.move(matching: uci) else { return false }
        return apply(move)
    }

    /// Accepts a SAN token, which is what reading a PGN produces.
    @discardableResult
    public mutating func apply(san: String) -> Bool {
        guard let move = SAN.move(for: san, in: state) else { return false }
        return apply(move)
    }

    /// Plays a move from the position after `ply` moves, keeping whatever used to be played
    /// from there as a Variation.
    ///
    /// This is what browsing back and playing something else does. Three cases, and the
    /// third is the interesting one: past the end is not a thing, playing the move that is
    /// already there just carries on down the line that exists, and anything else branches.
    @discardableResult
    public mutating func play(_ move: Move, atPly ply: Int) -> Bool {
        guard (0...plies.count).contains(ply) else { return false }
        if ply == plies.count { return apply(move) }
        if plies[ply].uci == move.uci { return true }

        guard var branch = rewound(to: ply), branch.apply(move) else { return false }

        // The line being left behind, with everything that hung off it, becomes an
        // alternative to the move now standing in its place.
        let abandoned = Array(plies[ply...])
        var replacement = branch.plies[ply]
        replacement.variations = [abandoned]
        // Alternatives already recorded at this point are alternatives to the same position,
        // so they belong to the new move too rather than to the line that just left.
        replacement.variations.append(contentsOf: abandoned.first?.variations ?? [])

        plies = Array(plies[..<ply]) + [replacement]
        state = branch.state
        return true
    }

    /// Records a line as an alternative to the move at `ply`. Used when reading a PGN, where
    /// the brackets arrive after the move they belong to.
    public mutating func addVariation(_ variation: [Ply], atPly ply: Int) {
        guard plies.indices.contains(ply), !variation.isEmpty else { return }
        plies[ply].variations.append(variation)
    }

    /// The lines that were played from the same position as the move at `ply`.
    public func variations(atPly ply: Int) -> [[Ply]] {
        plies.indices.contains(ply) ? plies[ply].variations : []
    }

    /// Takes a Variation as the line to carry on with, and puts the line it replaces where it
    /// came from. Stepping into a branch, in other words.
    @discardableResult
    public mutating func promoteVariation(_ index: Int, atPly ply: Int) -> Bool {
        guard plies.indices.contains(ply) else { return false }
        let alternatives = plies[ply].variations
        guard alternatives.indices.contains(index) else { return false }

        var chosen = alternatives[index]
        var abandoned = Array(plies[ply...])
        abandoned[0].variations = []

        var rest = alternatives
        rest.remove(at: index)
        chosen[0].variations = [abandoned] + rest

        guard let head = rewound(to: ply) else { return false }
        var rebuilt = head
        for step in chosen {
            guard rebuilt.apply(uci: step.uci) else { return false }
        }
        // Replay dropped the evaluations and the nested variations, so they go back on.
        for (offset, step) in chosen.enumerated() {
            rebuilt.plies[ply + offset].evaluation = step.evaluation
            rebuilt.plies[ply + offset].variations = step.variations
        }
        self = rebuilt
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard !plies.isEmpty else { return false }
        let shortened = Array(plies.dropLast())
        guard let previous = Rules.probe(startFEN: startFEN, moves: shortened.map(\.uci))
        else { return false }
        plies = shortened
        state = previous
        return true
    }

    /// The Game as it stood after `ply` moves, for stepping through a Review.
    ///
    /// Replaying is what recomputes the Position, but it would also throw away what replaying
    /// cannot know — the Scores a Review recorded and the Variations that hang off the moves
    /// — so those are carried across afterwards.
    public func rewound(to ply: Int) -> Game? {
        guard (0...plies.count).contains(ply) else { return nil }
        guard var game = Game(startFEN: startFEN) else { return nil }
        for played in plies.prefix(ply) {
            guard game.apply(uci: played.uci) else { return nil }
        }
        for index in 0..<ply {
            game.plies[index].evaluation = plies[index].evaluation
            game.plies[index].variations = plies[index].variations
        }
        return game
    }

    public mutating func setEvaluation(_ score: Score?, atPly ply: Int) {
        guard plies.indices.contains(ply) else { return }
        plies[ply].evaluation = score
    }

    /// PGN's result token for however the Game stands.
    public var resultToken: String {
        switch state.outcome {
        case .ongoing: "*"
        case .checkmate: state.sideToMove == .white ? "0-1" : "1-0"
        case .stalemate, .fiftyMoveRule, .threefoldRepetition, .insufficientMaterial:
            "1/2-1/2"
        }
    }
}
