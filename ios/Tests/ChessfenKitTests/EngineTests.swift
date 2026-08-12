import ChessfenKit
import Foundation
import Synchronization
import Testing

/// The weights, found by path rather than copied into the test bundle: they are 112 MiB,
/// and duplicating them into every build product to run the tests is a poor trade.
enum Nets {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ChessfenKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ios
        .appendingPathComponent("Resources/Nets")

    static let big = directory.appendingPathComponent("nn-c288c895ea92.nnue")
    static let small = directory.appendingPathComponent("nn-37f18f62d772.nnue")

    static var arePresent: Bool {
        FileManager.default.fileExists(atPath: big.path)
            && FileManager.default.fileExists(atPath: small.path)
    }
}

/// One engine for the whole suite, because building a thread pool and a table per test
/// would dominate the run — and because there is only ever one in the app either. One
/// engine means one search, so these tests run in order rather than at once; a second
/// analysis would legitimately supersede the first and truncate its stream.
private let shared: EngineService? = {
    guard Nets.arePresent else { return nil }
    return try? EngineService(
        bigNetURL: Nets.big,
        smallNetURL: Nets.small,
        configuration: .init(threads: 2, hashMegabytes: 64, multiPV: 3)
    )
}()

/// Serialized because the tests share one engine, and one engine is one search: a second
/// analysis legitimately supersedes the first and truncates its stream, so running these
/// at once would have them stealing each other's answers.
@Suite("Stockfish engine", .serialized)
struct EngineTests {
    private func engine() throws -> EngineService {
    try #require(shared, "the NNUE weights are missing — see ios/README.md")
}

    @Test("the engine starts once its weights are where it was told")
    func engineStarts() throws {
        let service = try engine()
        #expect(service.setOption("Threads", "2"))
        #expect(!service.setOption("Nonexistent Option", "1"))
    }

    @Test("a missing net is refused rather than taking the process with it")
    func aMissingNetIsRefused() {
        // Stockfish answers a failed net load with exit(EXIT_FAILURE), which in an app means
        // the process simply vanishes. The bridge checks the files first; this is that check.
        let absent = Nets.directory.appendingPathComponent("nn-000000000000.nnue")
        #expect(throws: EngineService.StartupFailure.networkMissing) {
            _ = try EngineService(bigNetURL: absent, smallNetURL: absent)
        }
    }

    @Test("a file too small to be a net is refused too")
    func aTruncatedNetIsRefused() throws {
        let stub = FileManager.default.temporaryDirectory
            .appendingPathComponent("chessfen-truncated.nnue")
        try Data(repeating: 0, count: 1024).write(to: stub)
        defer { try? FileManager.default.removeItem(at: stub) }

        #expect(throws: EngineService.StartupFailure.networkTooSmall) {
            _ = try EngineService(bigNetURL: stub, smallNetURL: stub)
        }
    }

    @Test("an analysis deepens, and every line it reports is playable")
    func analysisDeepens() async throws {
        let service = try engine()
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        var snapshots: [Analysis] = []
        for await analysis in service.analyse(game, budget: .depth(10)) {
            snapshots.append(analysis)
        }

        #expect(snapshots.count > 1, "one snapshot per Depth was expected, got \(snapshots.count)")
        #expect(snapshots.map(\.depth) == snapshots.map(\.depth).sorted())
        #expect(snapshots.last?.depth == 10)

        let final = try #require(snapshots.last)
        #expect(final.lines.count == 3, "MultiPV was 3, got \(final.lines.count)")
        #expect(final.nodes > 0)
        for line in final.lines {
            let move = try #require(line.bestMove)
            #expect(game.state.move(matching: move) != nil, "\(move) is not legal here")
            #expect(!line.san.isEmpty)
        }
        // The opening is roughly level, and no reasonable search says otherwise.
        if case .centipawns(let value) = final.best?.score {
            #expect(abs(value) < 100, "the start position scored \(value)")
        } else {
            Issue.record("the start position should not be a mate score")
        }
    }

    @Test("a mate is found and named as a mate")
    func mateIsFound() async throws {
        let service = try engine()
        // Back-rank mate in one: Ra8#.
        let game = try #require(Game(startFEN: "6k1/5ppp/8/8/8/8/8/R3K2R w - - 0 1"))

        var last: Analysis?
        for await analysis in service.analyse(game, budget: .depth(8)) { last = analysis }
        let best = try #require(last?.best)
        #expect(best.score == .mate(in: 1))
        #expect(best.san.first == "Ra8#")
    }

    @Test("scores are White-relative whichever side is to move")
    func scoresAreWhiteRelative() async throws {
        let service = try engine()
        // White is a queen up. The sign must not depend on whose turn it is.
        let whiteToMove = try #require(Game(startFEN: "4k3/8/8/8/8/8/8/3QK3 w - - 0 1"))
        let blackToMove = try #require(Game(startFEN: "4k3/8/8/8/8/8/8/3QK3 b - - 0 1"))

        var white: Analysis?
        for await analysis in service.analyse(whiteToMove, budget: .depth(8)) { white = analysis }
        var black: Analysis?
        for await analysis in service.analyse(blackToMove, budget: .depth(8)) { black = analysis }

        for (label, analysis) in [("white to move", white), ("black to move", black)] {
            let score = try #require(analysis?.best?.score)
            switch score {
            case .centipawns(let value):
                #expect(value > 200, "\(label) scored \(value); White is a queen up")
            case .mate(let moves):
                #expect(moves > 0, "\(label) scored #\(moves); White is the one mating")
            }
        }
    }

    @Test("a move budget produces a legal move and honours the clock")
    func bestMoveRespectsTheClock() async throws {
        let service = try engine()
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: ["e2e4", "e7e5"]))

        let started = ContinuousClock.now
        let move = try #require(await service.bestMove(for: game, budget: .time(.milliseconds(400))))
        let elapsed = ContinuousClock.now - started

        #expect(game.state.legalMoves.contains(move))
        #expect(elapsed < .seconds(4), "took \(elapsed) for a 400 ms budget")
    }

    @Test("an unbounded analysis stops when it is asked to")
    func unboundedAnalysisStops() async throws {
        let service = try engine()
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        var seen = 0
        for await _ in service.analyse(game, budget: .untilStopped) {
            seen += 1
            // Ending the loop terminates the stream, which stops the engine — the same path a
            // screen being dismissed takes.
            if seen >= 3 { break }
        }
        #expect(seen == 3)

        await service.waitForSearchToFinish()
        // And the engine is usable straight afterwards, rather than wedged.
        let after = await service.bestMove(for: game, budget: .depth(4))
        #expect(after != nil)
    }

    @Test("a review scores every ply at one uniform depth")
    func reviewScoresEveryPly() async throws {
        let service = try engine()
        let game = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: ["e2e4", "e7e5", "g1f3", "b8c6"])
        )

        await service.clear()
        let scores = await service.review(game, depth: 6)
        #expect(scores.count == game.plies.count)
        #expect(scores.allSatisfy { $0 != nil })

        // Four sensible opening moves; nobody is winning yet, and nobody is mated.
        for score in scores.compactMap({ $0 }) {
            guard case .centipawns(let value) = score else {
                Issue.record("an opening ply should not score as a mate")
                continue
            }
            #expect(abs(value) < 150, "an opening ply scored \(value)")
        }
    }

    @Test("a review of a game with no moves is empty rather than nil-padded")
    func reviewOfAnEmptyGameIsEmpty() async throws {
        let service = try engine()
        let game = try #require(Game(startFEN: PGN.standardStartFEN))
        #expect(await service.review(game, depth: 4).isEmpty)
    }

    // ------------------------------------------------- the app coming and going
    //
    // Every test here resumes in a `defer`: the suite shares one engine, so an engine left
    // paused by a failing test would hang every test after it rather than fail its own.

    /// Runs `work` and gives up after `limit`, `nil` meaning it did not finish in time.
    ///
    /// Every test below turns on an unbounded search *ending*, and the way each of them regresses
    /// is that it does not: the stream never finishes and the test hangs. A hung suite is a much
    /// worse report than a failed expectation, so the deadline is what turns one into the other.
    private func within<T: Sendable>(
        _ limit: Duration, _ work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            // Cancelling the loser terminates its stream, which stops the engine — so a search
            // that outran the deadline does not carry on into the next test.
            group.cancelAll()
            return first
        }
    }

    @Test("a paused engine does not take up a standing analysis")
    func aPausedEngineRefusesAStandingAnalysis() async throws {
        let service = try engine()
        defer { service.resume() }
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        service.pause()
        #expect(service.isPaused)

        // The stream ends without a snapshot, rather than deepening forever: an unbounded
        // Analysis belongs to a screen someone is looking at, and the screen asks again on the
        // way back.
        let seen = await within(.seconds(2)) {
            var count = 0
            for await _ in service.analyse(game, budget: .untilStopped) { count += 1 }
            return count
        }
        #expect(seen == 0, "a paused engine started a standing analysis")
    }

    @Test("pausing stops the search already running")
    func pausingStopsTheRunningSearch() async throws {
        let service = try engine()
        defer { service.resume() }
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        // The loop never breaks out. The app going away is the only thing that can end this
        // stream, so this passes only if the pause is what ended it.
        let seen = try #require(
            await within(.seconds(5)) {
                var count = 0
                for await _ in service.analyse(game, budget: .untilStopped) {
                    count += 1
                    if count == 2 { service.pause() }
                }
                return count
            },
            "pausing did not stop the search that was running"
        )
        #expect(seen >= 2)
    }

    @Test("an analysis refused while away is taken up once the app is back")
    func aResumedEngineTakesUpTheAnalysis() async throws {
        let service = try engine()
        defer { service.resume() }
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        service.pause()
        let whileAway = await within(.seconds(2)) {
            var count = 0
            for await _ in service.analyse(game, budget: .untilStopped) { count += 1 }
            return count
        }
        #expect(whileAway == 0)

        service.resume()
        #expect(!service.isPaused)
        let afterwards = try #require(
            await within(.seconds(5)) {
                var count = 0
                for await _ in service.analyse(game, budget: .untilStopped) {
                    count += 1
                    if count >= 2 { break }
                }
                return count
            },
            "a resumed engine never reported an analysis"
        )
        #expect(afterwards == 2)
        await service.waitForSearchToFinish()
    }

    @Test("a bounded search waits for the app rather than coming back empty")
    func aBoundedSearchHoldsWhilePaused() async throws {
        let service = try engine()
        defer { service.resume() }
        let game = try #require(Game(startFEN: PGN.standardStartFEN))

        let answered = Atomic<Bool>(false)
        service.pause()
        let search = Task {
            let score = await service.evaluate(game, budget: .depth(6))
            answered.store(true, ordering: .releasing)
            return score
        }

        // Depth 6 from the start position takes a few milliseconds, so this is long enough for
        // an engine that ignored the gate to have finished and given itself away.
        try await Task.sleep(for: .milliseconds(400))
        // Read out before asserting: `Atomic` is non-copyable, and `#expect` needs to be handed
        // something it can capture.
        let answeredWhilePaused = answered.load(ordering: .acquiring)
        #expect(!answeredWhilePaused, "a paused engine answered a bounded search")

        service.resume()
        #expect(await search.value != nil, "a held search should run on the way back, not fail")
    }

    /// A long game of quiet, obviously legal moves.
    ///
    /// Length is the point rather than the chess: this is the game the Review tests below pause
    /// in the middle of, and there has to *be* a middle. Every pawn one square, then the pieces
    /// onto the squares the pawns left, so nothing here needs checking for legality by eye — and
    /// no move repeats a position, which would have the engine scoring draws instead of thinking.
    private static let longGame = [
        "a2a3", "a7a6", "b2b3", "b7b6", "c2c3", "c7c6", "d2d3", "d7d6",
        "e2e3", "e7e6", "f2f3", "f7f6", "g2g3", "g7g6", "h2h3", "h7h6",
        // The knights go where the d- and e-pawns came from: a pawn on every third-rank square
        // has blocked a3/c3/f3/h3 already.
        "b1d2", "b8d7", "g1e2", "g8e7",
        "c1b2", "c8b7", "f1g2", "f8g7", "d1c2", "d8c7",
        "a1b1", "a8b8", "h1g1", "h8g8",
    ]

    @Test("a review makes no progress while the app is away")
    func aReviewHoldsWhileTheAppIsAway() async throws {
        let service = try engine()
        defer { service.resume() }
        let game = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: Self.longGame)
        )

        let reported = Atomic<Int>(0)
        await service.clear()
        let reviewed = Task {
            await service.review(game, depth: 10) { _, _ in
                reported.wrappingAdd(1, ordering: .relaxed)
            }
        }

        // Caught by watching rather than by sleeping a guessed interval: the pause has to land
        // while there are plies still to do, and how long that takes is a fact about the
        // machine. A Review that finished before it could be interrupted proves nothing, so it
        // fails the test rather than passing it quietly.
        var caught = 0
        for _ in 0..<400 {
            let done = reported.load(ordering: .acquiring)
            if done >= 1, done < game.plies.count {
                caught = done
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        service.pause()
        #expect(caught > 0, "the review was never caught mid-flight — lengthen the game")

        // The regression this is here for. Pausing stops the running search, and the ply loop
        // used to start the next ply regardless: the rest of the game would be scored while the
        // app was away, at whatever Depth each search happened to reach before the next stop.
        // A Review whose Scores are not all at one Depth cannot be compared against itself,
        // which is the only thing it is for.
        let atPause = reported.load(ordering: .acquiring)
        try await Task.sleep(for: .milliseconds(400))
        let afterWaiting = reported.load(ordering: .acquiring)
        // Plus one for the ply that was already in flight when the pause landed and finished
        // before it took effect. Anything beyond that is the Review carrying on regardless.
        #expect(
            afterWaiting <= atPause + 1,
            "a paused review scored \(afterWaiting - atPause) more plies"
        )

        service.resume()
        let scores = await reviewed.value
        #expect(scores.count == game.plies.count)
        #expect(scores.allSatisfy { $0 != nil }, "a paused review left holes: \(scores)")
    }
}
