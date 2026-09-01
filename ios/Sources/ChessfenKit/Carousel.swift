/// Where a whole Line arrived, as against where it started.
///
/// A carousel that only recites moves is a carousel nobody learns from: you watch five plies go by,
/// the position is different, and the difference is exactly what a beginner cannot see. So the end
/// of the line is compared with the start and the difference is said in one sentence, out of the
/// same fixed templates over checkable facts the rest of the layer uses (docs/adr/0018, 0020).
public struct LineOutcome: Hashable, Sendable {
    /// How many plies were walked.
    public let steps: Int
    /// The clauses, in the order they are said. Kept apart from `sentence` so a test can name one
    /// without matching a whole paragraph.
    public let clauses: [String]
    /// 「5 步之后，d5 里坐着一个赶不走的马，你的王边少了 2 个守卫。」
    public var sentence: String {
        guard !clauses.isEmpty else { return "\(steps) 步之后，位置没什么实质变化。" }
        return "\(steps) 步之后，\(clauses.joined(separator: "，"))。"
    }
}

extension Game {
    /// What a Line adds up to, from the point of view of the side to move now.
    ///
    /// Nil when the Line will not replay from this position — an honest refusal, because a sentence
    /// about a line that was never played is a sentence about nothing.
    ///
    /// Three facts and no more: what was taken, what got a square it cannot be thrown off, and what
    /// the side's own king lost. Each one is a count anybody can go and check on the board, and each
    /// clause is omitted when its count is zero rather than being written as a zero.
    public func outcome(of line: [String]) -> LineOutcome? {
        guard !line.isEmpty,
            let beforePieces = BoardRenderer.placement(state.fen),
            let beforeControl = Rules.control(startFEN: startFEN, moves: uciMoves)
        else { return nil }
        let mover = state.sideToMove
        let opponent = mover.opposite

        var end = self
        for san in line {
            guard end.apply(san: san) else { return nil }
        }
        guard let afterPieces = BoardRenderer.placement(end.state.fen),
            let afterControl = Rules.control(startFEN: end.startFEN, moves: end.uciMoves)
        else { return nil }

        var clauses: [String] = []

        // What was taken, named rather than scored: "1 个马" is a thing to look for on the board
        // where "+2.9" is a thing to be told.
        func lost(_ colour: PieceColour) -> [(PieceKind, Int)] {
            PieceKind.allCases.compactMap { kind -> (PieceKind, Int)? in
                func count(_ pieces: [Square: Piece]) -> Int {
                    pieces.values.count { $0.colour == colour && $0.kind == kind }
                }
                let gone = count(beforePieces) - count(afterPieces)
                return gone > 0 ? (kind, gone) : nil
            }
        }
        func list(_ losses: [(PieceKind, Int)]) -> String {
            losses.map { "\($0.1) 个\($0.0.name)" }.joined(separator: "、")
        }
        let mine = lost(mover)
        let theirs = lost(opponent)
        if !mine.isEmpty || !theirs.isEmpty {
            let took = theirs.isEmpty ? "你没吃到子" : "你吃了对方 \(list(theirs))"
            let gave = mine.isEmpty ? "自己一个子没丢" : "自己丢了 \(list(mine))"
            clauses.append("\(took)，\(gave)")
        }

        // A piece of yours standing where their pawns can never reach it. The one positional fact
        // in the language a club player already uses, and the reason the line was worth watching.
        let planted = afterPieces.compactMap { square, piece -> (Square, Piece)? in
            guard piece.colour == mover, piece.kind != .pawn, piece.kind != .king,
                beforePieces[square]?.colour != mover,
                Rules.isHole(at: square, for: opponent, pieces: afterPieces)
            else { return nil }
            return (square, piece)
        }
        // Furthest into their half first, then the dearest piece, then by square — a sentence that
        // names a square has to name the same square every time it is asked.
        let outpost = planted.min { one, other in
            func depth(_ square: Square) -> Int { mover == .white ? square.rank : 7 - square.rank }
            if depth(one.0) != depth(other.0) { return depth(one.0) > depth(other.0) }
            if one.1.kind.rawValue != other.1.kind.rawValue {
                return one.1.kind.rawValue > other.1.kind.rawValue
            }
            return one.0.index < other.0.index
        }
        if let outpost {
            clauses.append("\(outpost.0) 里坐着一个赶不走的\(outpost.1.kind.name)")
        }

        // And what your own king lost while all that was going on — counted in guards and not in
        // squares, because "two fewer guards" is what a player can act on. The ring is the one the
        // king ends on: the claim is about what is looking after it *now* against what was looking
        // after those same squares before, which is the question a player asks after a line.
        if let king = afterPieces.first(where: { $0.value.colour == mover && $0.value.kind == .king })
        {
            var dropped = 0
            for file in (king.key.file - 1)...(king.key.file + 1) where (0..<8).contains(file) {
                for rank in (king.key.rank - 1)...(king.key.rank + 1)
                where (0..<8).contains(rank) && !(file == king.key.file && rank == king.key.rank) {
                    let square = Square(file: file, rank: rank)
                    let fall =
                        beforeControl.attackers(of: square, by: mover)
                        - afterControl.attackers(of: square, by: mover)
                    if fall > 0 { dropped += fall }
                }
            }
            if dropped > 0 { clauses.append("你的王边少了 \(dropped) 个守卫") }
        }

        return LineOutcome(steps: line.count, clauses: clauses)
    }
}

/// A Line being played out on the main board, one Ply at a time.
///
/// 走马灯: the concrete form of "seeing five moves ahead", as against being told that one should.
/// Ephemeral by definition — no Variation is made, nothing reaches the PGN, and leaving it restores
/// the position exactly, because a Line is a hypothesis and nothing in it was played (docs/adr/0020).
/// It costs no engine time either: the Line is the one the Review already stored.
public struct Walk: Hashable, Sendable {
    public let line: [String]
    /// How many plies of it are on the board: 0 is the position the Line starts from.
    public var step: Int
    /// Where the whole line arrives — computed once, because it is about the line and not about
    /// where in it you have got to.
    public let outcome: LineOutcome

    public var isAtStart: Bool { step == 0 }
    public var isAtEnd: Bool { step == line.count }
    /// The plies played so far.
    public var played: [String] { Array(line.prefix(step)) }
    /// What the Line still expects, which is the second net the 要害格 layer reads at each step.
    public var remaining: [String] { Array(line.dropFirst(step)) }

    public init(line: [String], step: Int, outcome: LineOutcome) {
        self.line = line
        self.step = step
        self.outcome = outcome
    }
}
