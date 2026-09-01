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
        /// A hole somebody can actually get to. The difference between a weakness on paper and a
        /// weakness with a knight walking towards it, which is the difference a player can act on.
        case outpost
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
    /// Who can come and stand here, and whether they could be thrown out again. Nil when nobody
    /// can reach it soon enough for the answer to be about this position.
    public let occupation: Occupation?
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
        case .outpost: 2
        case .hole: 3
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
        var candidates: [Square: (kind: KeySquare.Kind, isGain: Bool, by: Occupation?)] = [:]
        for (squares, isGain) in [(change.gained, true), (change.lost, false)] {
            for square in squares {
                // A square you took is one *you* would come and use; one you let go of is one
                // *they* would. Who walks there is the whole difference between an outpost and a
                // weakness, and it is decided by which way the square went.
                let comer = isGain ? mover : mover.opposite
                let occupation = Rules.occupation(of: square, by: comer, pieces: pieces)
                let kind: KeySquare.Kind?
                if ownRing.contains(square) {
                    kind = .ownKing
                } else if enemyRing.contains(square) {
                    kind = .enemyKing
                } else if Rules.isHole(
                    at: square, for: isGain ? mover.opposite : mover, pieces: pieces
                ) {
                    // A hole nobody can get to is a weakness on paper. A hole with a piece walking
                    // towards it is the thing that actually happens to you.
                    kind = occupation != nil ? .outpost : .hole
                } else {
                    kind = nil
                }
                if let kind { candidates[square] = (kind, isGain, occupation) }
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
                    occupation: candidate.by,
                    note: Self.note(
                        square: square, kind: candidate.kind, isGain: candidate.isGain,
                        proof: proof,
                        isTheKingsOwnSquare: kings[
                            candidate.kind == .ownKing ? mover : mover.opposite
                        ] == square,
                        arrival: candidate.by
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
        isTheKingsOwnSquare: Bool, arrival: Occupation?
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
            case (.hole, true, _), (.outpost, true, _):
                "\(square) 成了永久据点：对方的兵再也管不到这格"
            case (.hole, false, _), (.outpost, false, _):
                "\(square) 成了永久弱格：自己的兵再也管不回这格"
            }
        let because: String =
            switch proof {
            case .occupied(let step, let san):
                "引擎第 \(step) 步就走 \(san)"
            case .persisted(let plies):
                "走完引擎这 \(plies) 步，它还是这样"
            }
        // Claim, mechanism, evidence — in that order, and the engine's word closes it.
        return "\(what)。\(walk(arrival, kind: kind, isGain: isGain))\(because)。"
    }

    /// The clause that turns a square into something that happens: which piece comes and how far
    /// away it is.
    ///
    /// Said only when somebody can actually get there — a sentence about a piece four moves away is
    /// a sentence about a different position. Whether it could be thrown out again is said only
    /// for the king-ring kinds: a hole is *defined* by nothing being able to throw anybody out, so
    /// saying it twice is saying it once and wasting a line.
    private static func walk(_ arrival: Occupation?, kind: KeySquare.Kind, isGain: Bool) -> String {
        guard let arrival else { return "" }
        let whose = isGain ? "自己的" : "对方的"
        let stay =
            switch (kind, arrival.canBeDislodged) {
            case (.ownKing, false), (.enemyKing, false): "，兵赶不走它"
            case (.ownKing, true), (.enemyKing, true): "，不过兵还能把它赶走"
            default: ""
            }
        return "\(whose)\(arrival.piece.kind.name)从 \(arrival.from) 走 \(arrival.moves) 步就到\(stay)。"
    }
}

/// Who can actually come and stand on a square, how soon, and whether they could be thrown out.
///
/// "You let go of d5" is a fact about a map. "Their knight is three moves from d5 and no pawn of
/// yours will ever attack it again" is a fact about the game, and it is the one a player can do
/// something about. This is the second half of the 然后呢 (docs/adr/0020).
public struct Occupation: Hashable, Sendable {
    public let piece: Piece
    public let from: Square
    public let target: Square
    /// How many moves that piece needs, counting from one.
    public let moves: Int
    /// Where it goes, one square per move, ending on the target. What the board draws as a route,
    /// and what makes the claim checkable: a route a player can follow is a route they can argue
    /// with.
    public let route: [Square]
    /// Whether a pawn of the other side can ever attack the target. False is what makes a square
    /// an outpost rather than a stop: whoever gets there stays.
    public let canBeDislodged: Bool
}

extension Rules {
    /// How far one piece is from a square, ignoring everything the other side does.
    ///
    /// The approximation is deliberate and has to be said out loud: this walks one piece over the
    /// board as it stands, treating its own side's pieces as walls and the other side's as squares
    /// it may land on. Nobody replies. What it answers is "how far away is that knight", which is
    /// the question a player actually asks about an outpost — not "can this be forced", which is a
    /// search and would cost a Stint (docs/adr/0019).
    ///
    /// Nil when the piece cannot get there within `horizon` moves. Three by default: a piece four
    /// moves away from a square is not a fact about this position.
    public static func route(
        to target: Square, from origin: Square, pieces: [Square: Piece], horizon: Int = 3
    ) -> [Square]? {
        guard let piece = pieces[origin], origin != target else { return nil }
        var seen: Set<Square> = [origin]
        var edge: [(square: Square, path: [Square])] = [(origin, [])]
        for _ in 0..<horizon {
            var next: [(square: Square, path: [Square])] = []
            for (square, path) in edge {
                for step in steps(of: piece, from: square, pieces: pieces) {
                    if step == target { return path + [step] }
                    guard !seen.contains(step) else { continue }
                    // A square with somebody on it can be landed on and not walked through: what
                    // happens after a capture is a different position, and this one is not it.
                    seen.insert(step)
                    if pieces[step] == nil { next.append((step, path + [step])) }
                }
            }
            edge = next
            if edge.isEmpty { break }
        }
        return nil
    }

    /// Where one piece may move in one move, by geometry alone: no checks, no pins, no turn order.
    private static func steps(
        of piece: Piece, from square: Square, pieces: [Square: Piece]
    ) -> [Square] {
        func free(_ file: Int, _ rank: Int) -> Square? {
            guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
            let there = Square(file: file, rank: rank)
            return pieces[there]?.colour == piece.colour ? nil : there
        }
        func slide(_ directions: [(Int, Int)]) -> [Square] {
            var found: [Square] = []
            for (df, dr) in directions {
                var file = square.file + df
                var rank = square.rank + dr
                while let there = free(file, rank) {
                    found.append(there)
                    if pieces[there] != nil { break }
                    file += df
                    rank += dr
                }
            }
            return found
        }
        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let slanted = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        switch piece.kind {
        case .knight:
            return [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
                .compactMap { free(square.file + $0.0, square.rank + $0.1) }
        case .bishop: return slide(slanted)
        case .rook: return slide(straight)
        case .queen: return slide(straight + slanted)
        case .king: return (straight + slanted).compactMap { free(square.file + $0.0, square.rank + $0.1) }
        case .pawn:
            // Forwards onto an empty square, sideways onto an occupied one. A pawn's two ways of
            // moving are the reason it cannot be treated as a slider with a short leash.
            let ahead = piece.colour == .white ? 1 : -1
            var found: [Square] = []
            if (0..<8).contains(square.rank + ahead) {
                let one = Square(file: square.file, rank: square.rank + ahead)
                if pieces[one] == nil {
                    found.append(one)
                    let home = piece.colour == .white ? 1 : 6
                    if square.rank == home {
                        let two = Square(file: square.file, rank: square.rank + ahead * 2)
                        if pieces[two] == nil { found.append(two) }
                    }
                }
                for file in [square.file - 1, square.file + 1] where (0..<8).contains(file) {
                    let take = Square(file: file, rank: square.rank + ahead)
                    if let other = pieces[take], other.colour != piece.colour { found.append(take) }
                }
            }
            return found
        }
    }

    /// The soonest any piece of `colour` can come and stand on `square`, with what would happen to
    /// it when it got there. Nil when nobody can inside the horizon.
    ///
    /// Kings are left out. A king walking to an outpost is not a plan.
    public static func occupation(
        of square: Square, by colour: PieceColour, pieces: [Square: Piece], horizon: Int = 3
    ) -> Occupation? {
        var best: Occupation?
        for (origin, piece) in pieces
        where piece.colour == colour && piece.kind != .king && origin != square {
            guard let route = route(to: square, from: origin, pieces: pieces, horizon: horizon),
                best == nil || route.count < best!.moves
            else { continue }
            best = Occupation(
                piece: piece,
                from: origin,
                target: square,
                moves: route.count,
                route: route,
                canBeDislodged: !isHole(at: square, for: colour.opposite, pieces: pieces)
            )
            if route.count == 1 { break }
        }
        return best
    }
}
