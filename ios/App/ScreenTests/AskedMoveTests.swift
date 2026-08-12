import ChessfenKit
import Testing

@testable import Chessfen

/// What 让引擎走 does, and what filing a game stops the screen asking about. Neither is visible in a
/// picture — a press is a moment and the screenshots are of states — so they are checked here.
@MainActor
@Suite(.serialized)
struct AskedMove {
    private static let italian = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"]

    private static let searching = [
        Analysis(
            depth: 12,
            selectiveDepth: 17,
            lines: [
                Line(score: .centipawns(24), uciMoves: ["b1a3"], san: ["Na3"])
            ],
            timeMilliseconds: 300
        ),
        Analysis(
            depth: 26,
            selectiveDepth: 34,
            lines: [
                Line(score: .centipawns(38), uciMoves: ["d2d4", "e5d4"], san: ["d4", "exd4"])
            ],
            timeMilliseconds: 2_400
        ),
    ]

    private func session(_ engine: ScriptedEngine) throws -> GameSession {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession(game: game, origin: .fresh)
        session.attach(engine: engine, library: nil)
        return session
    }

    /// The search runs in a task of its own, so what it has reported is known a hop later — which is
    /// exactly as true of the screen as it is of this test.
    private func hop() async {
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Held time is thinking time: the search runs while the button is down and reports as it goes.
    @Test("holding the engine button starts a search that reports how far it has got")
    func holdingReports() async throws {
        let session = try session(ScriptedEngine(Self.searching, isEndless: true))

        session.beginAskedMove()
        await hop()

        #expect(session.isThinking)
        #expect(session.searchProgress?.depth == 26, "the deepest snapshot so far")
        #expect(session.searchProgress?.selectiveDepth == 34)
        #expect(session.searchProgress?.seconds == 2.4)
        #expect(session.game.plies.count == 8, "nothing is played while it is being held")
    }

    /// Letting go plays what it found, for whichever colour was on the clock.
    @Test("letting go plays the move the search settled on")
    func lettingGoPlays() async throws {
        let session = try session(ScriptedEngine(Self.searching, isEndless: true))

        session.beginAskedMove()
        await hop()
        session.endAskedMove()

        #expect(session.game.plies.count == 9, "letting go plays at once")
        #expect(session.game.plies.last?.san == "d4")
        #expect(!session.isThinking)
    }

    /// A press is a drag that keeps reporting, and the button hears it before it hears itself.
    @Test("a press that reports twice still only starts one search")
    func pressingTwiceAsksOnce() async throws {
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        let session = try session(engine)

        session.beginAskedMove()
        session.beginAskedMove()
        await hop()

        #expect(engine.searchCount == 1, "one thumb, one search")
        #expect(session.isThinking)
    }

    /// A tap is a press let go of before the engine has said a word, and it still moves.
    @Test("a tap plays the move the board was already recommending")
    func tapPlaysTheArrow() async throws {
        let session = try session(ScriptedEngine(Self.searching, isEndless: true))
        // A standing Analysis, arrived at the way the screen gets one: the engine advising while it
        // is the player's move.
        session.retune()
        await hop()
        #expect(session.analysis?.bestMove == "d2d4", "the arrow on the board")

        session.beginAskedMove()
        session.endAskedMove()

        #expect(session.game.plies.count == 9)
        #expect(session.game.plies.last?.san == "d4")
    }

    /// Practice hides what the engine thinks, not what it is doing.
    @Test("a search asked for while practising reports its progress but not its opinion")
    func practisingKeepsTheStopwatch() async throws {
        let session = try session(ScriptedEngine(Self.searching, isEndless: true))
        session.setPractising(true)

        session.beginAskedMove()
        await hop()

        #expect(session.searchProgress?.depth == 26)
        #expect(session.analysis == nil, "no Score reaches the screen while practising")
    }

    /// A game somebody has filed has been looked at and kept, so the screen stops asking about the
    /// pieces it once was not sure of.
    @Test("filing a game into a collection puts the piece question to rest")
    func filedGameStopsAsking() throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R w KQkq - 0 5"
        let game = try #require(Game(startFEN: fen))
        let shaky: Set<Square> = [Square("c6")!, Square("f6")!]

        let unfiled = GameSession(
            game: game, origin: .recognised, shaky: shaky,
            tags: [PGN.Tag("Event", "Chessfen")]
        )
        #expect(unfiled.canEditPosition)
        #expect(unfiled.unconfirmedSquares == shaky)

        let filed = GameSession(
            game: game, origin: .recognised, shaky: shaky,
            tags: [PGN.Tag("Event", "西西里防御")]
        )
        #expect(!filed.canEditPosition)
        #expect(filed.unconfirmedSquares.isEmpty)
        // And filing survives the next move being written: `pgn` must not file it back out.
        #expect(filed.pgn.tag("Event") == "西西里防御")
    }
}
