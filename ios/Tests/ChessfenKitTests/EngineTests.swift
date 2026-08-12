import ChessfenKit
import Foundation
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
}
