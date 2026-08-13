import ChessfenKit
import Testing

@testable import Chessfen

/// How long the engine gets over a move it plays for a colour it controls, and what happens when
/// it holds both of them.
///
/// None of this is visible in a picture: a clock is a number handed to a search, and a game the
/// app plays against itself is a thing that happens over time rather than a state to photograph.
@MainActor
@Suite(.serialized)
struct EngineClock {
    /// The Italian, eight plies in, White to move — so whoever holds White is on the clock the
    /// moment the session is tuned.
    private static let italian = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"]

    /// One search that answers and ends, which is what a bounded one does: the engine reports what
    /// it found and the stream finishes, and that is what makes it play the move.
    private static let searching = [
        Analysis(
            depth: 26,
            selectiveDepth: 34,
            lines: [
                Line(score: .centipawns(38), uciMoves: ["d2d4", "e5d4"], san: ["d4", "exd4"])
            ],
            timeMilliseconds: 2_400
        )
    ]

    private func session(
        _ engine: ScriptedEngine, controllers: [PieceColour: Controller]
    ) throws -> GameSession {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession(game: game, controllers: controllers, origin: .fresh)
        session.attach(engine: engine, library: nil)
        // What the screen does in `onAppear`, and what makes the engine start.
        session.retune()
        return session
    }

    /// The search runs in a task of its own, so what it was asked is known a hop later — which is
    /// exactly as true of the screen as it is of this test.
    private func hop() async {
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Nobody is on the clock, so nobody is playing: the app plays itself, at the clock it names.
    @Test("with both sides on the engine the app plays itself, three seconds a move")
    func selfPlayMovesOnItsOwn() async throws {
        let engine = ScriptedEngine(Self.searching)
        let session = try session(engine, controllers: [.white: .engine, .black: .engine])
        await hop()

        #expect(session.isSelfPlaying)
        #expect(session.thinkingTime == .fixed(seconds: 3))
        #expect(session.game.plies.count == 9, "nobody touched the board and it moved")
        #expect(session.game.plies.last?.san == "d4")
        #expect(
            engine.budgets.allSatisfy { $0 == .time(.seconds(3)) },
            "every move of a game with no player in it is played on the named clock"
        )
    }

    /// Against a person it is still Mirrored Time, and the second engine is what changes it.
    @Test("the clock is the mirror until the engine is playing itself")
    func theSecondEngineNamesAClock() async throws {
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        let session = try session(engine, controllers: [.white: .engine, .black: .hand])
        await hop()

        #expect(session.thinkingTime == .mirrored)
        #expect(
            engine.budgets.last == .time(MirroredTime.opening),
            "nothing has been played by hand yet, so there is nothing to mirror"
        )

        session.setController(.engine, for: .black)
        await hop()

        #expect(session.thinkingTime == .fixed(seconds: 3))
        #expect(engine.budgets.last == .time(.seconds(3)))
    }

    /// A clock chosen by hand stands for both colours and both kinds of game.
    @Test("changing the clock takes effect on the move being thought about now")
    func changingTheClockRestartsTheSearch() async throws {
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        let session = try session(engine, controllers: [.white: .engine, .black: .engine])
        await hop()
        #expect(engine.budgets.last == .time(.seconds(3)))

        session.setThinkingTime(.fixed(seconds: 10))
        await hop()

        #expect(session.thinkingTime == .fixed(seconds: 10))
        #expect(
            engine.budgets.last == .time(.seconds(10)),
            "the move being waited for is the one this is reached for because of"
        )
        #expect(session.isThinking, "and it is still that move being thought about")
        #expect(session.game.plies.count == 8)
    }

    /// The mirror needs somebody to mirror. Choosing it and then leaving the board to the engine
    /// says which clock it is really on rather than quietly meaning the opening second for ever.
    @Test("self-play overrules a standing choice of the mirror")
    func selfPlayOverrulesTheMirror() async throws {
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        let session = try session(engine, controllers: [.white: .engine, .black: .hand])
        session.setThinkingTime(.fixed(seconds: 10))
        session.setThinkingTime(.mirrored)
        #expect(session.thinkingTime == .mirrored)

        session.setController(.engine, for: .black)
        await hop()

        #expect(session.thinkingTime == .fixed(seconds: 3))
        #expect(engine.budgets.last == .time(.seconds(3)))

        // And it is a refusal for as long as it applies, not a rewriting of what was chosen: the
        // mirror comes back the moment there is somebody to mirror.
        session.setController(.hand, for: .black)
        #expect(session.thinkingTime == .mirrored)
    }

    /// Browsing is where a machine game is paused: the engine only plays from the latest position.
    @Test("stepping back stops the engine playing itself, and coming back carries on")
    func steppingBackStopsSelfPlay() async throws {
        let engine = ScriptedEngine(Self.searching)
        let session = try session(engine, controllers: [.white: .engine, .black: .engine])
        await hop()
        #expect(session.game.plies.count == 9)

        session.step(by: -1)
        await hop()

        #expect(!session.isEngineTurn, "nothing is played from an earlier position")
        #expect(session.game.plies.count == 9)
        #expect(
            engine.budgets.last == .untilStopped,
            "what runs instead is the advice the position on screen deserves"
        )
    }
}
