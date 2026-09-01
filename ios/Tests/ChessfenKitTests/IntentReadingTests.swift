import ChessfenKit
import Testing

private func square(_ name: String) throws -> Square {
    try #require(Square(name))
}

private func position(_ fen: String) throws -> Game {
    try #require(Game(startFEN: fen))
}

private func move(_ uci: String, in game: Game) throws -> Move {
    try #require(game.state.move(matching: uci))
}

/// An engine gives a number and a sequence of moves and never a reason. This is the reason, derived
/// from the moves with the same rules code that tells a declared Intent false (docs/adr/0020).
@Test("a capture that wins material reads as 吃, on the square it happened")
func aWinningCaptureReadsAsTake() throws {
    // The white pawn on e4 takes an undefended pawn on d5.
    let game = try position("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
    let read = Intent.read(try move("e4d5", in: game), in: game)
    #expect(read == .claim(.take, try square("d5")))
    #expect(read.label == "吃 d5")
}

@Test("a trade that does not lose reads as 换, not as 吃")
func anEvenTradeReadsAsTrade() throws {
    // Same capture, but the pawn on d5 is defended by one on c6: level, not winning.
    let game = try position("4k3/8/2p5/3p4/4P3/8/8/4K3 w - - 0 1")
    #expect(Intent.read(try move("e4d5", in: game), in: game) == .claim(.trade, try square("d5")))
}

@Test("a move that newly threatens a piece it outnumbers reads as 攻")
func aNewThreatReadsAsAttack() throws {
    // The rook swings to a5 and looks at an undefended knight on d5 that nothing guards.
    let game = try position("4k3/8/8/3n4/8/8/8/R3K3 w - - 0 1")
    let read = Intent.read(try move("a1a5", in: game), in: game)
    #expect(read == .claim(.attack, try square("d5")))
}

@Test("the most valuable piece newly threatened is the one named")
func theDearestThreatWins() throws {
    // A knight fork: Ne6 looks at the queen on d8 and the rook on g7, and neither is defended.
    let game = try position("k2q4/6r1/8/8/3N4/8/8/4K3 w - - 0 1")
    let read = Intent.read(try move("d4e6", in: game), in: game)
    #expect(read == .claim(.attack, try square("d8")), "the queen, not the rook")
}

@Test("a hanging piece moving to safety reads as 躲, naming what it ran from")
func runningAwayReadsAsFlee() throws {
    // The white rook on a1 is attacked by the black bishop on b2 and defended by nothing. It runs
    // up to a4, which the bishop cannot reach and from which it threatens nothing — so 躲 is the
    // whole of what the move is for. (Rb1 and Ra2 both read as 攻 b2, and rightly: they do both.)
    let game = try position("4k3/8/8/8/8/8/1b6/R3K3 w - - 0 1")
    let read = Intent.read(try move("a1a4", in: game), in: game)
    #expect(read == .claim(.flee, try square("b2")))
}

@Test("a move that guards a hanging piece of your own reads as 护")
func guardingAHangingPieceReadsAsDefend() throws {
    // The white knight on e4 is looked at by the rook on e7 and by nothing of White's. The rook
    // swings to e1 and now guards it up the file.
    let game = try position("7k/4r3/8/8/4N3/8/8/R6K w - - 0 1")
    let read = Intent.read(try move("a1e1", in: game), in: game)
    #expect(read == .claim(.defend, try square("e4")))
}

@Test("a move that steps into a line reads as 挡")
func interposingReadsAsBlock() throws {
    // White is in check from the rook on e8, which the black king guards, so taking it is not on
    // and threatening it proves nothing. The rook steps into the line instead.
    let game = try position("3kr3/8/8/8/R7/8/8/4K3 w - - 0 1")
    let read = Intent.read(try move("a4e4", in: game), in: game)
    #expect(read == .claim(.block, try square("e4")))
}

/// 占 in this app means *control*, not occupation (docs/adr/0018): the rook that takes the fifth
/// rank holds d5, and the knight that goes and stands on d5 does not — a piece does not attack the
/// square it is on. So a move that takes a square from a distance reads as 占, and a move that walks
/// onto one is named by the layer instead, as a 据点 (docs/adr/0020).
@Test("a move that takes a square from a distance reads as 占")
func takingASquareFromADistanceReadsAsHold() throws {
    let game = try position("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
    let read = Intent.read(try move("a1a5", in: game), in: game)
    #expect(read == .claim(.hold, try square("d5")))
}

@Test("walking onto a square is not 占 of that square")
func walkingOntoASquareIsNotHold() throws {
    // The knight standing on d5 does not attack d5, so nothing about d5's control improved and the
    // reading cannot name it. What it names instead is a square the knight genuinely covers from
    // there — f6, the most central of the four it newly holds in Black's half.
    let game = try position("4k3/8/8/8/8/2N5/8/4K3 w - - 0 1")
    let read = Intent.read(try move("c3d5", in: game), in: game)
    #expect(read != .claim(.hold, try square("d5")), "the knight on d5 does not attack d5")
    #expect(read == .claim(.hold, try square("f6")))
}

/// A verb that cannot be wrong does not get printed, and a move whose reason none of the seven can
/// carry comes back 说不清 — exactly as a player's does (docs/adr/0018).
@Test("a move none of the seven can honestly carry reads as 说不清")
func anUnreadableMoveIsSaidToBeUnreadable() throws {
    // A king shuffling on an empty board: nothing taken, nothing threatened, nothing rescued, and
    // the square it steps onto was already its own.
    let game = try position("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    #expect(Intent.read(try move("e1d1", in: game), in: game) == .unclear)
}

/// Every verb this prints is one the app would agree with if somebody declared it. That is the
/// property the reading is built on: it proposes, and `check` confirms, so the two cannot drift.
@Test("whatever is read of a move, checking that same claim agrees")
func theReadingAndTheCheckerAgree() throws {
    let positions = [
        ("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5"),
        ("4k3/8/2p5/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5"),
        ("4k3/8/8/3n4/8/8/8/R3K3 w - - 0 1", "a1a5"),
        ("4k3/8/8/8/8/8/1b6/R3K3 w - - 0 1", "a1a4"),
        ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "a1a5"),
        ("k2q4/6r1/8/8/3N4/8/8/4K3 w - - 0 1", "d4e6"),
        ("4k3/8/8/8/8/2N5/8/4K3 w - - 0 1", "c3d5"),
        ("7k/4r3/8/8/4N3/8/8/R6K w - - 0 1", "a1e1"),
        ("3kr3/8/8/8/R7/8/8/4K3 w - - 0 1", "a4e4"),
    ]
    for (fen, uci) in positions {
        let game = try position(fen)
        let played = try move(uci, in: game)
        let read = Intent.read(played, in: game)
        guard read != .unclear else { continue }
        let check = try #require(read.check(played, in: game))
        #expect(check.held, "\(uci) read as \(read.label) and then failed its own check")
        #expect(check.note != nil, "and the fact it held on is a fact about the board")
    }
}

@Test("the reading is the same every time it is asked")
func theReadingIsDeterministic() throws {
    // A fork with two equally valuable pieces on the end of it: a dictionary must not be the one
    // deciding which of them the sentence names.
    let game = try position("k2r4/6r1/8/8/3N4/8/8/4K3 w - - 0 1")
    let played = try move("d4e6", in: game)
    let answers = (0..<30).map { _ in Intent.read(played, in: game) }
    #expect(Set(answers).count == 1, "thirty asks, one answer")
}

// ------------------------------------------------------------------ a whole line

@Test("a line reads as the recommendation's own verb plus one later move of the mover's")
func aLineReadsAsAPlan() throws {
    // White's knight goes to d5 where it looks at the undefended rook on f6, Black's king steps
    // aside, and the knight takes it — 「攻 f6，第 3 步再 吃 f6」.
    let game = try position("4k3/8/5r2/8/8/2N5/8/4K3 w - - 0 1")
    let reading = try #require(game.reading(of: ["Nd5", "Kd8", "Nxf6"]))
    #expect(reading.opening.step == 1)
    #expect(reading.opening.san == "Nd5")
    #expect(reading.opening.intent == .claim(.attack, try square("f6")))
    let later = try #require(reading.later)
    #expect(later.step == 3)
    #expect(later.san == "Nxf6")
    #expect(later.intent == .claim(.take, try square("f6")))
    #expect(reading.sentence == "攻 f6，第 3 步再 吃 f6")
}

@Test("only the mover's own moves are what the recommendation is for")
func theOpponentsMovesAreNotThePlan() throws {
    let game = try position("4k3/8/5r2/8/8/2N5/8/4K3 w - - 0 1")
    let reading = try #require(game.reading(of: ["Nd5", "Kd8", "Nxf6"]))
    // Step 2 is Black's. It is never the later half, whatever it reads as.
    #expect(reading.later?.step != 2)
}

@Test("a line whose rest reads as nothing says only what the first move is for")
func aLineWithNoPlanSaysOnlyTheFirstMove() throws {
    let game = try position("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
    let reading = try #require(game.reading(of: ["Ra5", "Kd8"]))
    #expect(reading.later == nil, "one move of the mover's in the line, and nothing to add")
    #expect(reading.sentence == "占 d5")
}

@Test("an empty line, and one that will not replay, are refused rather than guessed at")
func anUnreadableLineIsRefused() throws {
    let game = try position("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    #expect(game.reading(of: []) == nil)
    #expect(game.reading(of: ["Qh8"]) == nil, "not a move in this position")
    // And a first move that reads as nothing still comes back: "the engine played this and the app
    // cannot say why" is a true thing for a screen to admit.
    let unreadable = try #require(game.reading(of: ["Kd1"]))
    #expect(unreadable.opening.intent == .unclear)
    #expect(unreadable.sentence == Intent.unclearLabel)
}
