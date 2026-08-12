import ChessfenKit
import Testing

private let start = PGN.standardStartFEN

@Test("a game written out and read back is the same game")
func pgnRoundTripsAStandardGame() throws {
    var game = try #require(
        Game(startFEN: start, uciMoves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"])
    )
    game.setEvaluation(.centipawns(31), atPly: 0)
    game.setEvaluation(.centipawns(-12), atPly: 1)
    game.setEvaluation(.mate(in: 5), atPly: 4)

    let written = PGN(game: game, tags: [.init("White", "Felix"), .init("Black", "Stockfish 18")])
    let read = try PGN(parsing: written.text)

    #expect(read.game.startFEN == game.startFEN)
    #expect(read.game.uciMoves == game.uciMoves)
    #expect(read.game.plies.map(\.san) == game.plies.map(\.san))
    #expect(read.game.plies.map(\.evaluation) == game.plies.map(\.evaluation))
    #expect(read.tag("White") == "Felix")
    #expect(read.tag("Black") == "Stockfish 18")
    #expect(read.tag("Result") == "*")
    // The standard start needs no FEN tag.
    #expect(read.tag("FEN") == nil)
    #expect(!written.text.contains("SetUp"))
}

@Test("a game recognised from a picture carries its position in the tags")
func pgnRoundTripsARecognisedPosition() throws {
    // Knight on c6, not c7: from c7 it would be attacking the black king while white is
    // to move, which is not a position that can exist.
    let recognised = "r3k3/8/2N5/8/8/8/8/4K3 w q - 0 1"
    var game = try #require(Game(startFEN: recognised))
    let played = game.apply(uci: "c6e5")
    #expect(played)

    let written = PGN(game: game)
    #expect(written.text.contains("[SetUp \"1\"]"))
    #expect(written.text.contains("[FEN \"\(recognised)\"]"))

    let read = try PGN(parsing: written.text)
    #expect(read.game.startFEN == recognised)
    #expect(read.game.uciMoves == ["c6e5"])
}

@Test("a game that starts with black to move numbers its first move correctly")
func pgnNumbersABlackFirstStart() throws {
    let position = "r3k3/2N5/8/8/8/8/8/4K3 b q - 0 17"
    var game = try #require(Game(startFEN: position))
    let kingMoved = game.apply(uci: "e8d8")
    let knightTook = game.apply(uci: "c7a8")
    #expect(kingMoved)
    #expect(knightTook)

    let text = PGN(game: game).text
    #expect(text.contains("17... Kd8 18. Nxa8"))

    let read = try PGN(parsing: text)
    #expect(read.game.uciMoves == ["e8d8", "c7a8"])
}

@Test("the result reflects how the game actually ended")
func pgnWritesTheResult() throws {
    let mated = try #require(
        Game(startFEN: start, uciMoves: ["f2f3", "e7e5", "g2g4", "d8h4"])
    )
    #expect(PGN(game: mated).text.contains("[Result \"0-1\"]"))
    #expect(PGN(game: mated).text.hasSuffix("Qh4# 0-1\n"))

    let drawn = try #require(Game(startFEN: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
    #expect(PGN(game: drawn).text.contains("[Result \"1/2-1/2\"]"))
}

@Test("the noise real PGN files carry is skipped")
func pgnSkipsCommentsVariationsAndAnnotations() throws {
    let text = """
        [Event "Something"]
        [Site "Somewhere"]
        [Date "2026.08.12"]
        [Round "3"]
        [White "A"]
        [Black "B"]
        [Result "1-0"]

        1. e4 $1 {a comment with [%eval 0.25] inside} e5!? (1... c5 2. Nf3 {sicilian}
        (2... d6 3. d4)) 2. Nf3 ; a line comment
        Nc6 3. Bb5 1-0
        """

    let read = try PGN(parsing: text)
    #expect(read.game.plies.map(\.san) == ["e4", "e5", "Nf3", "Nc6", "Bb5"])
    #expect(read.game.plies[0].evaluation == .centipawns(25))
    #expect(read.game.plies[1].evaluation == nil)
    #expect(read.tag("Round") == "3")
}

@Test("a PGN with no FEN tag starts from the standard position")
func pgnWithoutFenStartsFromScratch() throws {
    let read = try PGN(parsing: "1. d4 d5 *")
    #expect(read.game.startFEN == start)
    #expect(read.game.uciMoves == ["d2d4", "d7d5"])
}

@Test("an impossible move stops the parse instead of being ignored")
func pgnRejectsAnIllegalMove() throws {
    #expect(throws: PGN.ParseError.illegalMove("Qh5", afterPlies: 1)) {
        try PGN(parsing: "1. e4 Qh5 *")
    }
}

@Test("an unusable starting position stops the parse and says why")
func pgnRejectsAnUnusableStartingPosition() throws {
    let text = "[FEN \"8/8/8/8/8/8/8/8 w - - 0 1\"]\n\n*"
    #expect(throws: PGN.ParseError.unusableStartingPosition(.missingKing)) {
        try PGN(parsing: text)
    }
}

@Test("quotes and backslashes in tag values survive the round trip")
func pgnEscapesTagValues() throws {
    let game = try #require(Game(startFEN: start))
    let written = PGN(game: game, tags: [.init("Event", #"a "quoted" \ event"#)])
    let read = try PGN(parsing: written.text)
    #expect(read.tag("Event") == #"a "quoted" \ event"#)
}

@Test("scores survive the trip through PGN's eval comments")
func evaluationTextRoundTrips() {
    let scores: [Score] = [
        .centipawns(0), .centipawns(31), .centipawns(-250), .centipawns(1234),
        .mate(in: 3), .mate(in: -2),
    ]
    for score in scores {
        #expect(Score(pgnText: score.pgnText) == score, "\(score.pgnText)")
    }
}
