import ChessfenKit
import Testing

private func square(_ name: String) throws -> Square {
    try #require(Square(name))
}

private func pieces(_ fen: String) throws -> [Square: Piece] {
    try #require(BoardRenderer.placement(fen))
}

// ------------------------------------------------------------------- the holes

/// A hole is not "undefended". It is "and it can never be defended", which is a claim about pawns
/// and about the one thing pawns cannot do.
@Test("a square no pawn of one side can ever attack again is a hole for that side")
func aHoleIsASquareNoPawnCanComeBackTo() throws {
    // Black pawns on c5 and e5: d5 can never be attacked by a black pawn again, because the two
    // that could have are past it and pawns do not go backwards.
    let board = try pieces("4k3/8/8/2p1p3/8/8/8/1N2K3 w - - 0 1")
    #expect(Rules.isHole(at: try square("d5"), for: .black, pieces: board))
    // And the same square for White is not: a white pawn is not there, but this asks whether one
    // could ever be, and c2 or e2 would do it. There are none of either, so it is a hole for White
    // too — the test that matters is the next one.
    #expect(Rules.isHole(at: try square("d5"), for: .white, pieces: board))
}

@Test("a pawn that could still advance to attack a square keeps it off the list")
func aPawnThatCanStillComeIsNotAHole() throws {
    // Black pawn on c7: it can walk to c6 and attack d5 whenever Black likes.
    let board = try pieces("4k3/2p5/8/4p3/8/8/8/1N2K3 w - - 0 1")
    #expect(!Rules.isHole(at: try square("d5"), for: .black, pieces: board))
    // A pawn already attacking the square is the same answer, arrived at sooner.
    #expect(!Rules.isHole(at: try square("d5"), for: .black, pieces: try pieces("4k3/8/2p5/8/8/8/8/1N2K3 w - - 0 1")))
}

@Test("a hole on the back ranks is not named, because nobody outposts there")
func holesAreOnlyLookedForInTheMiddle() throws {
    let board = try pieces("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    // An empty board makes every square unattackable by a pawn for ever. Only the four middle
    // ranks are named, or the layer would be drawing squares to have something to draw.
    #expect(Rules.isHole(at: try square("d4"), for: .white, pieces: board))
    #expect(Rules.isHole(at: try square("d6"), for: .white, pieces: board))
    #expect(!Rules.isHole(at: try square("d2"), for: .white, pieces: board))
    #expect(!Rules.isHole(at: try square("d8"), for: .white, pieces: board))
}

// -------------------------------------------------------------- the two nets

/// The whole point, in one test: of everything Nc3 changed hands over, exactly one square is drawn
/// — the one the engine walks a knight onto two moves later.
@Test("the square the engine's line lands on is the one that gets drawn")
func theLineDecidesWhichSquareMatters() throws {
    let game = try #require(
        Game(startFEN: "4k3/8/8/2p1p3/8/8/8/1N2K3 w - - 0 1", uciMoves: ["b1c3"])
    )
    // Nc3 changes hands over a4, b5, d5, e4 and more; several of them are holes in Black's
    // position, so the rules net alone proposes a scattering.
    let change = try #require(game.lastMoveControlChange)
    #expect(change.gained.count > 3, "the rules net has plenty to choose from")

    let key = game.keySquares(continuation: ["Ke7", "Nd5+"])
    #expect(key.count == 1, "one square, out of everything that changed")
    let d5 = try #require(key.first)
    #expect(d5.square == (try square("d5")))
    #expect(d5.kind == .hole)
    #expect(d5.isGain)
    #expect(d5.mover == .white)
    #expect(d5.proof == .occupied(step: 2, san: "Nd5+"))
    #expect(d5.note.contains("d5"))
    #expect(d5.note.contains("永久据点"))
    #expect(d5.note.contains("第 2 步"))
}

@Test("no line, nothing drawn — and that is the answer rather than a fallback")
func withoutALineNothingIsDrawn() throws {
    let game = try #require(
        Game(startFEN: "4k3/8/8/2p1p3/8/8/8/1N2K3 w - - 0 1", uciMoves: ["b1c3"])
    )
    #expect(game.keySquares(continuation: []).isEmpty)
    // And a game nobody has moved in has no last Ply to be about.
    let fresh = try #require(Game(startFEN: PGN.standardStartFEN))
    #expect(fresh.keySquares(continuation: ["e4", "e5"]).isEmpty)
}

/// The weaker of the two proofs, and the reason it is weaker: nobody went there, so all the layer
/// may claim is that the line never took the change back.
@Test("a square the line never visits is allowed one claim, and only one")
func aSquareNobodyVisitsPersistsAtMostAlone() throws {
    let game = try #require(
        Game(startFEN: "4k3/8/8/2p1p3/8/8/8/1N2K3 w - - 0 1", uciMoves: ["b1c3"])
    )
    // A line that walks the kings about and never touches anything the knight took.
    let key = game.keySquares(continuation: ["Kd8", "Kd1", "Ke8", "Ke1"])
    #expect(key.count <= 1, "one square at most when the engine went nowhere near any of them")
    if let only = key.first {
        guard case .persisted(let plies) = only.proof else {
            Issue.record("a square nobody visited cannot claim to have been occupied")
            return
        }
        #expect(plies == 4)
        #expect(only.note.contains("走完引擎这 4 步"))
    }
}

/// Beside your own king is the one place where letting go of a square is not a matter of taste,
/// so it is a kind of its own and it sorts first.
@Test("a square let go of beside the mover's own king is named as that")
func lettingGoBesideYourOwnKingIsItsOwnKind() throws {
    // The queen guards d7 beside her own king and then walks out to g5. One move later the white
    // rook is standing on d7 — which is what "对方的攻势从这里进来" means, said as a fact.
    let game = try #require(
        Game(startFEN: "3qk3/R7/8/8/8/8/8/4K3 b - - 0 1", uciMoves: ["d8g5"])
    )
    let key = game.keySquares(continuation: ["Rd7"])
    let d7 = try #require(key.first { $0.square == (try? square("d7")) })
    #expect(d7.mover == .black)
    #expect(d7.kind == .ownKing)
    #expect(!d7.isGain)
    #expect(d7.proof == .occupied(step: 1, san: "Rd7"))
    #expect(d7.note.contains("自己王的旁边"))
    #expect(d7.note.contains("对方的攻势从这里进来"))
}

/// A square in the *other* king's ring is where an attack is built rather than where one arrives,
/// so it is a kind of its own too, and it sorts after your own king's.
@Test("a square taken beside the other king is named as that")
func takingBesideTheOtherKingIsItsOwnKind() throws {
    // White's rook swings to the seventh; f7 beside the black king changes hands, and the engine
    // walks the rook onto it next move.
    let game = try #require(
        Game(startFEN: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", uciMoves: ["a1a7"])
    )
    let key = game.keySquares(continuation: ["Kd8", "Rf7"])
    let f7 = try #require(key.first { $0.square == (try? square("f7")) })
    #expect(f7.mover == .white)
    #expect(f7.kind == .enemyKing)
    #expect(f7.isGain)
    #expect(f7.note.contains("对方王的旁边"))
}

@Test("never more than the limit, however much the engine's line touches")
func theLimitHolds() throws {
    let game = try #require(
        Game(startFEN: "3qk3/R7/8/8/8/8/8/4K3 b - - 0 1", uciMoves: ["d8g5"])
    )
    let line = ["Rd7", "Kf8", "Rf7+", "Kg8"]
    #expect(game.keySquares(continuation: line).count <= 3)
    #expect(game.keySquares(continuation: line, limit: 1).count <= 1)
}

/// The ring includes the square the king is standing on, and "beside your own king" is the wrong
/// sentence about that one.
@Test("the square the king is standing on gets its own sentence")
func theKingsOwnSquareIsSaidDifferently() throws {
    // The queen on d8 is the only thing covering e8, where her own king stands. She walks away.
    let game = try #require(
        Game(startFEN: "3qk3/8/8/8/8/8/8/R3K3 b - - 0 1", uciMoves: ["d8g5"])
    )
    let key = game.keySquares(continuation: ["Rb1", "Ke7", "Rc1", "Kf6"])
    let e8 = try #require(key.first { $0.square == (try? square("e8")) })
    #expect(e8.kind == .ownKing)
    #expect(!e8.isGain)
    #expect(e8.note.contains("自己的王正站在上面"))
    #expect(!e8.note.contains("旁边"))
}
