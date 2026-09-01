/// A square the board judged worth drawing, and the reason it is worth drawing (docs/adr/0020).
///
/// The layer used to paint every square a move changed hands over — nine or ten of them, in two
/// colours, with a legend that counted them. That is a diff, and a player cannot act on a diff:
/// 「我管住了这些格，然后呢？」 A 要害格 answers the 然后呢, and answers it with something that can
/// be checked: a rules net said this square could matter, and the engine's own Line said it did.
public struct KeySquare: Hashable, Sendable {
    /// Why the rules net proposed this square. Three kinds and no more, because a fourth that
    /// cannot be told wrong is a fourth that teaches nothing (docs/adr/0018).
    public enum Kind: Hashable, Sendable {
        /// Beside the mover's own king. The one place where letting go of a square is not a
        /// matter of taste.
        case ownKing
        /// Beside the other king: where an attack is built.
        case enemyKing
        /// A square no pawn of the side that would have to challenge it can ever attack again.
        /// The difference between a square you lent out and one you gave away.
        case hole
    }

    /// How the engine's Line showed the square mattered. Both are facts about moves, not opinions
    /// about squares, which is what lets a sentence about either be told false.
    public enum Proof: Hashable, Sendable {
        /// A move of the Line lands on it, at this step counting from one.
        case occupied(step: Int, san: String)
        /// Nobody goes there, but after the whole Line has been played the square is still on the
        /// side the move put it on. A change that survives the answer is a change that stuck.
        case persisted(plies: Int)
    }

    public let square: Square
    public let kind: Kind
    /// The side that played the move all of this is about.
    public let mover: PieceColour
    /// Whether the move took a grip on the square or let go of it, from the mover's point of view.
    public let isGain: Bool
    public let proof: Proof
    /// One sentence over facts the rules code can check, in the style an Intent is judged in.
    public let note: String
}

extension KeySquare.Proof {
    /// Sooner is stronger, and a piece actually going there beats a square merely staying gone.
    /// Sorted ascending, so the smallest number is the most important square.
    var order: Int {
        switch self {
        case .occupied(let step, _): step
        case .persisted: Int.max
        }
    }

    var isOccupied: Bool {
        if case .occupied = self { return true }
        return false
    }
}

extension KeySquare.Kind {
    /// The tie-break when two squares are proven equally well. Your own king first: an attack
    /// arriving is worth more than an attack being prepared, which is worth more than a square.
    var order: Int {
        switch self {
        case .ownKing: 0
        case .enemyKing: 1
        case .hole: 2
        }
    }
}

extension Rules {
    /// Whether `colour` can ever attack `square` with a pawn again.
    ///
    /// A hole, in the ordinary chess sense: for White to attack a square, a white pawn has to
    /// stand one rank below it on a neighbouring file, and pawns do not go backwards — so if no
    /// white pawn is at or below that rank on either neighbouring file, none ever will be. That
    /// is what makes a hole different from a square that merely happens to be undefended: nothing
    /// the owner does can put it right.
    ///
    /// Blockers are deliberately not considered. A pawn that could reach the square in ten moves
    /// counts as being able to, because the claim being made is "never", and "never" should be
    /// hard to earn.
    public static func isHole(
        at square: Square, for colour: PieceColour, pieces: [Square: Piece]
    ) -> Bool {
        // Only in the four middle ranks. A hole on somebody's back rank is a hole nobody outposts
        // on, and naming it would be the layer drawing squares to have something to draw.
        guard (2...5).contains(square.rank) else { return false }
        for file in [square.file - 1, square.file + 1] where (0..<8).contains(file) {
            for (at, piece) in pieces
            where piece.kind == .pawn && piece.colour == colour && at.file == file {
                let couldReach =
                    colour == .white ? at.rank <= square.rank - 1 : at.rank >= square.rank + 1
                if couldReach { return false }
            }
        }
        return true
    }
}

extension Game {
    /// The squares worth drawing about the last Ply of this Game, most important first.
    ///
    /// `continuation` is the engine's expected Line from *this* position, in SAN — a Review's
    /// (docs/adr/0016) or the one a Reveal's search produced. It is the second of the two nets and
    /// it is the one that does the judging: the rules propose squares that *could* matter, and a
    /// square nothing in the next few moves goes near did not, whatever the rules thought of it.
    ///
    /// Empty when there is no last Ply, when the position will not replay, or when the Line is
    /// empty — which is the honest answer and not a fallback to painting everything.
    public func keySquares(continuation: [String], limit: Int = 3) -> [KeySquare] {
        guard !continuation.isEmpty,
            let change = lastMoveControlChange,
            let pieces = BoardRenderer.placement(state.fen),
            let before = rewound(to: plies.count - 1),
            let beforeControl = Rules.control(startFEN: before.startFEN, moves: before.uciMoves)
        else { return [] }

        let mover = change.mover
        let ownRing = kingRing(of: mover)
        let enemyRing = kingRing(of: mover.opposite)
        // The ring includes the square the king stands on, and that square needs its own sentence:
        // "beside your own king" is wrong about the square your king is on.
        let kings = Dictionary(
            uniqueKeysWithValues: pieces.compactMap { square, piece in
                piece.kind == .king ? (piece.colour, square) : nil
            }
        )

        // ---- the rules net: which of the squares that changed hands could matter at all
        var candidates: [Square: (kind: KeySquare.Kind, isGain: Bool)] = [:]
        for (squares, isGain) in [(change.gained, true), (change.lost, false)] {
            for square in squares {
                let kind: KeySquare.Kind?
                if ownRing.contains(square) {
                    kind = .ownKing
                } else if enemyRing.contains(square) {
                    kind = .enemyKing
                } else if Rules.isHole(
                    at: square, for: isGain ? mover.opposite : mover, pieces: pieces
                ) {
                    // A square you took that they can never challenge is an outpost; one you gave
                    // up that you can never challenge is a weakness. Same test, opposite side.
                    kind = .hole
                } else {
                    kind = nil
                }
                if let kind { candidates[square] = (kind, isGain) }
            }
        }
        guard !candidates.isEmpty else { return [] }

        // ---- the engine's net: walk the Line and see where it actually goes
        var walk = self
        var arrivals: [Square: (step: Int, san: String)] = [:]
        var played = 0
        for san in continuation {
            guard walk.apply(san: san), let move = walk.moveSquares(atPly: walk.plies.count)
            else { break }
            played += 1
            if arrivals[move.to] == nil { arrivals[move.to] = (played, san) }
        }
        guard played > 0,
            let endControl = Rules.control(startFEN: walk.startFEN, moves: walk.uciMoves)
        else { return [] }

        var found: [KeySquare] = []
        for (square, candidate) in candidates {
            let proof: KeySquare.Proof
            if let arrival = arrivals[square] {
                proof = .occupied(step: arrival.step, san: arrival.san)
            } else if endControl.grip(on: square, for: mover)
                != beforeControl.grip(on: square, for: mover)
            {
                // The move's own doing is still standing at the end of the Line, so the Line
                // never took it back — which is the weaker of the two proofs and still a proof.
                proof = .persisted(plies: played)
            } else {
                continue
            }
            found.append(
                KeySquare(
                    square: square,
                    kind: candidate.kind,
                    mover: mover,
                    isGain: candidate.isGain,
                    proof: proof,
                    note: Self.note(
                        square: square, kind: candidate.kind, isGain: candidate.isGain,
                        proof: proof,
                        isTheKingsOwnSquare: kings[
                            candidate.kind == .ownKing ? mover : mover.opposite
                        ] == square
                    )
                )
            )
        }

        found.sort {
            ($0.proof.order, $0.kind.order, $0.square.index)
                < ($1.proof.order, $1.kind.order, $1.square.index)
        }
        // A square the Line actually visits is worth drawing; when it visits none of them, one
        // square that merely stayed changed is all this is allowed to claim. This is where
        // "usually one, never more than three" comes from — it is a property of the proofs
        // available, not a number chosen to make the board look tidy.
        let visited = found.filter { $0.proof.isOccupied }
        return visited.isEmpty ? Array(found.prefix(1)) : Array(visited.prefix(limit))
    }

    /// One sentence, from a fixed template over facts the rules code can check.
    ///
    /// Colours are never named: everything here is said from the point of view of whoever played
    /// the move, and the panel above already says who that was. 自己的王 and 对方的兵 mean the same
    /// thing whichever side is reading.
    private static func note(
        square: Square, kind: KeySquare.Kind, isGain: Bool, proof: KeySquare.Proof,
        isTheKingsOwnSquare: Bool
    ) -> String {
        let what: String =
            switch (kind, isGain, isTheKingsOwnSquare) {
            case (.ownKing, false, true):
                "\(square) 松开了，自己的王正站在上面——现在没有子在守着它"
            case (.ownKing, true, true):
                "\(square) 补上了，自己的王正站在上面"
            case (.ownKing, false, _):
                "\(square) 松开了，就在自己王的旁边——对方的攻势从这里进来"
            case (.ownKing, true, _):
                "\(square) 补上了，就在自己王的旁边"
            case (.enemyKing, true, true):
                "\(square) 管住了，对方的王正站在上面"
            case (.enemyKing, true, _):
                "\(square) 管住了，就在对方王的旁边——攻势从这里开始"
            case (.enemyKing, false, _):
                "\(square) 松开了，对方王边少了一分压力"
            case (.hole, true, _):
                "\(square) 成了永久据点：对方的兵再也赶不走停在这儿的子"
            case (.hole, false, _):
                "\(square) 成了永久弱格：自己的兵再也管不回来"
            }
        let because: String =
            switch proof {
            case .occupied(let step, let san):
                "引擎第 \(step) 步就走 \(san)"
            case .persisted(let plies):
                "走完引擎这 \(plies) 步，它还是这样"
            }
        return "\(what)。\(because)。"
    }
}
