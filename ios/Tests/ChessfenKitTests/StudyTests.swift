import ChessfenKit
import Synchronization
import Testing

/// The one board as a study: browse back, answer, then be told (docs/adr/0015).
@MainActor
@Suite struct StudyTests {
    /// Four plies, so ply 3 is a real question with a real answer already in the file.
    private static let opening = ["e2e4", "e7e5", "g1f3", "b8c6"]

    private func game(_ moves: [String] = opening) throws -> Game {
        try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: moves))
    }

    private func session(_ engine: any Engine, moves: [String] = opening) throws -> GameSession {
        let session = GameSession.fresh(try game(moves))
        session.attach(engine: engine, library: nil)
        return session
    }

    /// The searches all run in tasks of their own, so their answers are known a hop later.
    private func hop() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func analysis(_ score: Score, best: (uci: String, san: String)? = nil) -> Analysis {
        Analysis(
            depth: 14,
            selectiveDepth: 18,
            lines: [
                Line(
                    score: score,
                    uciMoves: best.map { [$0.uci] } ?? [],
                    san: best.map { [$0.san] } ?? []
                )
            ],
            nodes: 1_000_000,
            nodesPerSecond: 1_000_000,
            timeMilliseconds: 500
        )
    }

    private func move(_ uci: String, in session: GameSession) throws -> Move {
        try #require(session.viewed.state.move(matching: uci))
    }

    // ---------------------------------------------------------------- a guess

    @Test("browsing back with the engine silent turns the board into a question")
    func browsingBackIsAStudy() throws {
        let session = try session(PositionalEngine([:]))
        #expect(!session.isStudying, "the latest position is a game, not a question")

        session.jump(toPly: 2)
        #expect(session.isStudying)
        #expect(session.guess == nil)
        #expect(session.reveal == nil)
        #expect(session.analysis == nil, "no Score, no arrow, no Lines")

        // With the opinion on, the same position is a position being read rather than asked.
        session.setPractising(false)
        #expect(!session.isStudying)
    }

    @Test("a move offered at a past ply goes on the board and not into the game")
    func offeringDoesNotPlay() throws {
        let session = try session(PositionalEngine([:]))
        session.jump(toPly: 2)
        let d4 = try move("d2d4", in: session)

        session.offer(d4)

        #expect(session.guess?.san == "d4")
        #expect(session.guess?.ply == 3)
        // On the board: the position being looked at is the one after the guess.
        #expect(session.viewed.plies.last?.san == "d4")
        // And not in the Game: the record still says Nf3, the file has not been written, and the
        // board is not taking a second answer.
        #expect(session.game.plies.map(\.san) == ["e4", "e5", "Nf3", "Nc6"])
        #expect(session.game.variations(atPly: 2).isEmpty)
        #expect(!session.isHandTurn)
    }

    @Test("taking a guess back leaves nothing behind, and so does moving the question")
    func withdrawingAndMovingOn() throws {
        let session = try session(PositionalEngine([:]))
        session.jump(toPly: 2)
        session.offer(try move("d2d4", in: session))

        session.withdrawGuess()
        #expect(session.guess == nil)
        #expect(session.viewed.plies.count == 2, "the board is back at the question")
        #expect(session.isHandTurn)

        // And a guess left standing goes away when the eye moves: the cursor is the question.
        session.offer(try move("d2d4", in: session))
        #expect(session.guess != nil)
        session.jump(toPly: 1)
        #expect(session.guess == nil)
        #expect(session.reveal == nil)
    }

    @Test("with the engine's opinion on, a move at a past ply is played, not offered")
    func opinionOnMeansTheOldBranching() throws {
        let session = try session(PositionalEngine([:]))
        session.setPractising(false)
        session.jump(toPly: 2)

        session.play(try move("d2d4", in: session))

        #expect(session.guess == nil, "nothing was being asked")
        #expect(session.game.plies[2].san == "d4", "it branched, the way it always has")
        #expect(session.game.variations(atPly: 2).first?.first?.san == "Nf3")
    }

    // ---------------------------------------------------------------- the reveal

    /// The scenario every reveal test uses: after 1. e4 e5 the engine likes Nf3 (+0.30); d4 is
    /// worth +0.10 and Qh5 is worth −4.00, and Nf3 as played comes out at +0.28.
    private func markedSession(guessing uci: String) async throws -> GameSession {
        let before = try game(["e2e4", "e7e5"])
        let afterD4 = try game(["e2e4", "e7e5", "d2d4"])
        let afterQh5 = try game(["e2e4", "e7e5", "d1h5"])
        let afterNf3 = try game(["e2e4", "e7e5", "g1f3"])
        let engine = PositionalEngine([
            before.state.fen: analysis(.centipawns(30), best: ("g1f3", "Nf3")),
            afterD4.state.fen: analysis(.centipawns(10)),
            afterQh5.state.fen: analysis(.centipawns(-400)),
            afterNf3.state.fen: analysis(.centipawns(28)),
        ])
        let session = try session(engine)
        session.jump(toPly: 2)
        session.offer(try move(uci, in: session))
        session.commitGuess()
        await hop()
        return session
    }

    @Test("a good guess is shown against the engine's move and the one that was played")
    func aGuessInsideTheBand() async throws {
        let session = try await markedSession(guessing: "d2d4")
        let reveal = try #require(session.reveal)

        #expect(reveal.guess == "d4")
        #expect(reveal.best == "Nf3")
        #expect(reveal.played == "Nf3")
        #expect(reveal.guessScore == .centipawns(10))
        #expect(reveal.bestScore == .centipawns(30))
        #expect(reveal.playedScore == .centipawns(28))
        #expect(reveal.depth == 14, "and the Depth all three were computed at is named")
        #expect(reveal.mover == .white)

        // Twenty centipawns off the engine's move: inside the band, and the band is the same one
        // a Review grades a played move by.
        #expect(reveal.lost == 20)
        #expect(reveal.quality == .fine)
        #expect(reveal.counts == true)
        #expect(!reveal.isSameAsBest)
        #expect(!reveal.isSameAsPlayed)
        #expect(!session.isRevealing)
        // Still nothing in the Game: a marked guess is not a played move.
        #expect(session.game.plies.map(\.san) == ["e4", "e5", "Nf3", "Nc6"])
    }

    @Test("a bad guess is told it is bad, on the same scale a played move is judged by")
    func aGuessOutsideTheBand() async throws {
        let session = try await markedSession(guessing: "d1h5")
        let reveal = try #require(session.reveal)

        #expect(reveal.guess == "Qh5")
        #expect(reveal.lost == 430)
        #expect(reveal.quality == .blunder)
        #expect(reveal.counts == false)
    }

    @Test("guessing the move that was played says so, and is not searched twice")
    func guessingWhatWasPlayed() async throws {
        let session = try await markedSession(guessing: "g1f3")
        let reveal = try #require(session.reveal)

        #expect(reveal.guess == "Nf3")
        #expect(reveal.isSameAsPlayed)
        #expect(reveal.isSameAsBest)
        #expect(reveal.playedScore == reveal.guessScore, "one position, one number")
        #expect(reveal.counts == true)
    }

    @Test("a guess worth keeping becomes a branch, with the line it replaced beside it")
    func keepingAGuess() async throws {
        let session = try await markedSession(guessing: "d2d4")
        session.keepGuess()

        #expect(session.guess == nil)
        #expect(session.reveal == nil)
        #expect(session.game.plies[2].san == "d4")
        #expect(session.game.variations(atPly: 2).first?.map(\.san) == ["Nf3", "Nc6"])
        #expect(session.cursor == 3)
    }

    // ---------------------------------------------------------------- the pass

    @Test("turning the engine's opinion on is what gives a Game its uniform pass")
    func theSwitchStartsThePass() async throws {
        let engine = ScriptedEngine([analysis(.centipawns(30), best: ("g1f3", "Nf3"))])
        let session = try session(engine)
        #expect(!session.game.isReviewed)
        #expect(session.reviewPass == nil)

        session.setPractising(false)
        await hop()

        let pass = try #require(session.reviewPass)
        #expect(pass.depth == GameSession.reviewDepth)
        #expect(pass.total == 4)
        #expect(pass.completed == 4)
        #expect(!pass.isRunning)
        #expect(session.game.isReviewed)
        #expect(session.game.reviewDepth == GameSession.reviewDepth)
        #expect(session.game.criticality()?.count == 4, "and so the Game can now be ranked")
    }

    @Test("a Game that already has a pass is not made to sit through another")
    func areviewedGameIsLeftAlone() async throws {
        let engine = ScriptedEngine([analysis(.centipawns(30), best: ("g1f3", "Nf3"))])
        let session = try session(engine)
        session.applyReview(
            [.centipawns(20), .centipawns(15), .centipawns(25), .centipawns(20)],
            startEvaluation: .centipawns(10),
            depth: 22
        )

        session.setPractising(false)
        await hop()

        #expect(session.reviewPass == nil, "nothing was started")
        #expect(session.game.reviewDepth == 22, "and the Depth it was done at stands")
    }

    @Test("a pass reports how far it has got, and leaving stops it without writing anything")
    func leavingStopsThePass() async throws {
        let engine = HeldEngine(analysis(.centipawns(30), best: ("g1f3", "Nf3")))
        let session = try session(engine)

        session.setPractising(false)
        await hop()
        let running = try #require(session.reviewPass)
        #expect(running.isRunning)
        #expect(running.total == 4)
        #expect(!session.game.isReviewed, "not yet: half a pass is not half a Review")

        session.suspend()
        await hop()

        #expect(session.reviewPass == nil)
        #expect(!session.game.isReviewed, "and it wrote nothing on the way out")
        #expect(session.game.criticality() == nil)
    }

    @Test("a move played while a pass runs throws the pass away rather than writing it")
    func aMoveDuringThePassInvalidatesIt() async throws {
        let engine = HeldEngine(analysis(.centipawns(30), best: ("g1f3", "Nf3")))
        let session = try session(engine)
        session.setPractising(false)
        await hop()
        #expect(session.reviewPass?.isRunning == true)

        // Somebody browses back and plays something else: the game the pass is about is gone.
        session.jump(toPly: 2)
        session.play(try move("d2d4", in: session))
        engine.release()
        await hop()

        #expect(session.reviewPass == nil)
        #expect(!session.game.isReviewed)
    }

    @Test("the worst moves are reachable from the session, and only once there is a pass")
    func worstMovesAreTheQuestions() async throws {
        let engine = ScriptedEngine([analysis(.centipawns(30), best: ("g1f3", "Nf3"))])
        let session = try session(engine)
        #expect(session.worstMoves() == nil, "no pass, no ranking, and no pretending otherwise")

        session.applyReview(
            [.centipawns(20), .centipawns(15), .centipawns(-400), .centipawns(-390)],
            startEvaluation: .centipawns(10),
            depth: 14
        )
        let worst = try #require(session.worstMoves())
        #expect(worst.first?.ply == 3)

        // And walking to one is what puts the board on the question it asks: the position the
        // move was played from, with the move itself still to come.
        session.setPractising(true)
        session.jump(toPly: (worst.first?.ply ?? 1) - 1)
        #expect(session.cursor == 2)
        #expect(session.isStudying)
    }
}

// ------------------------------------------------------------------------ fakes

/// An engine with an opinion per position, keyed by FEN. What a study needs and a script cannot
/// give: three searches of three different positions, each with its own answer.
private final class PositionalEngine: Engine {
    private let answers: [String: Analysis]
    private let cleared = Mutex(0)

    init(_ answers: [String: Analysis]) { self.answers = answers }

    /// How many times the search was told to forget what it knew — a study's Scores are only at
    /// the Depth they claim if nothing deeper was learned first.
    var clearCount: Int { cleared.withLock { $0 } }

    var isPaused: Bool { false }
    func pause() {}
    func resume() {}
    func clear() async { cleared.withLock { $0 += 1 } }

    func analyse(_ game: Game, budget: SearchBudget, lines: Int) -> AsyncStream<Analysis> {
        let answer = answers[game.state.fen]
        return AsyncStream { continuation in
            if let answer { continuation.yield(answer) }
            continuation.finish()
        }
    }

    func evaluate(_ game: Game, budget: SearchBudget) async -> Score? {
        answers[game.state.fen]?.best?.score
    }

    func review(
        _ game: Game, depth: Int, onPly: (@Sendable (Int, Score?) -> Void)?
    ) async -> [Score?] {
        game.plies.indices.map { ply in
            let score = answers[game.rewound(to: ply + 1)?.state.fen ?? ""]?.best?.score
            onPly?(ply, score)
            return score
        }
    }
}

/// An engine whose pass does not finish until it is let go — which is how a screen going away
/// mid-pass can be tested at all.
private final class HeldEngine: Engine {
    private let answer: Analysis
    private let released = Mutex(false)

    init(_ answer: Analysis) { self.answer = answer }

    func release() { released.withLock { $0 = true } }

    var isPaused: Bool { false }
    func pause() {}
    func resume() {}
    func clear() async {}

    func analyse(_ game: Game, budget: SearchBudget, lines: Int) -> AsyncStream<Analysis> {
        let answer = self.answer
        return AsyncStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }

    func evaluate(_ game: Game, budget: SearchBudget) async -> Score? { answer.best?.score }

    func review(
        _ game: Game, depth: Int, onPly: (@Sendable (Int, Score?) -> Void)?
    ) async -> [Score?] {
        onPly?(0, answer.best?.score)
        while !released.withLock({ $0 }) {
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return game.plies.indices.map { _ in answer.best?.score }
    }
}
