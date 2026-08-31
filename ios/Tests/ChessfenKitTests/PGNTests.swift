import ChessfenKit
import Testing

private let start = PGN.standardStartFEN

@Test("a game written out and read back is the same game")
func pgnRoundTripsAStandardGame() throws {
    var game = try #require(
        Game(startFEN: start, uciMoves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"])
    )
    game.applyReview(
        [.centipawns(31), .centipawns(-12), nil, nil, .mate(in: 5)],
        startEvaluation: .centipawns(20),
        depth: 18
    )

    let written = PGN(game: game, tags: [.init("White", "Felix"), .init("Black", "Stockfish 18")])
    let read = try PGN(parsing: written.text)

    #expect(read.game.startFEN == game.startFEN)
    #expect(read.game.uciMoves == game.uciMoves)
    #expect(read.game.plies.map(\.san) == game.plies.map(\.san))
    #expect(read.game.plies.map(\.evaluation) == game.plies.map(\.evaluation))
    // The Depth and the starting Score are as much a part of a Review as its per-ply Scores:
    // without them nothing read back from a file can be compared with anything.
    #expect(read.game.reviewDepth == 18)
    #expect(read.game.startEvaluation == .centipawns(20))
    #expect(read.game.plies.allSatisfy { $0.importedEvaluation == nil })
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
    // This file carries no Review Depth, so its `[%eval]` came from somebody else's engine at
    // a Depth nobody wrote down. It is kept — as theirs — and the Review's field stays empty,
    // which is what stops it from being ranked or called a mistake (docs/adr/0016).
    #expect(read.game.plies[0].importedEvaluation == .centipawns(25))
    #expect(read.game.plies[0].evaluation == nil)
    #expect(!read.game.isReviewed)
    #expect(read.game.reviewScore(atPly: 1) == nil)
    #expect(read.game.plies[1].importedEvaluation == nil)
    #expect(read.tag("Round") == "3")
    // The Sicilian aside is a real line and is kept. The bracket nested inside it says
    // "2... d6" where it is white's move, so it is not a line at all — it is dropped, and
    // dropping it does not cost the rest of the file.
    #expect(read.game.variations(atPly: 1).map { $0.map(\.san) } == [["c5", "Nf3"]])
    #expect(read.game.variations(atPly: 2).isEmpty)
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

@Test("setting a tag keeps its place, and nil takes it away")
func setTagKeepsOrder() throws {
    let game = try #require(Game(startFEN: start))
    var pgn = PGN(
        game: game,
        tags: [.init("Event", "Chessfen"), .init("Name", "第 002 题"), .init("Source", "识别")]
    )

    // A collection is written into the tag it already occupies. Re-adding it at the end would put
    // it after the movetext-adjacent tags and out of PGN's roster order, which is part of the file.
    pgn.setTag("Event", to: "啄木鸟全集")
    #expect(pgn.tags.map(\.name) == ["Event", "Name", "Source"])
    #expect(pgn.tag("Event") == "啄木鸟全集")

    pgn.setTag("Round", to: "7")
    #expect(pgn.tags.last?.name == "Round", "a tag that was not there goes on the end")

    pgn.setTag("Name", to: nil)
    #expect(pgn.tag("Name") == nil, "a name can be taken back off")
    #expect(pgn.tags.map(\.name) == ["Event", "Source", "Round"])

    // And all of it survives being written out and read back, which is the only claim that matters.
    let read = try PGN(parsing: pgn.text)
    #expect(read.tag("Event") == "啄木鸟全集")
    #expect(read.tag("Name") == nil)
}
