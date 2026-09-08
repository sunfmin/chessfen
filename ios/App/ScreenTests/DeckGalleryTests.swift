import ChessfenKit
import SwiftUI
import Testing

@testable import Chessfen

/// The deck under the board, one card per picture (docs/adr/0023).
///
/// Ten cards, ten PNGs, each with something real on it — a mate with its arrows, a shot, a
/// question with its verbs, a ranked square with its sentence. The other suite photographs the
/// *screen* in the states a game passes through; this one photographs the *cards*, side by side
/// and comparable, which is what anybody redesigning them has to be able to lay out on a table.
///
/// So the assertions here are deliberately thin: each says only that the card it named is the card
/// that drew and that the thing it exists to show is on it. The pictures are the point.
@MainActor
@Suite(.serialized)
struct DeckGallery {
    private static let italian = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"]
    /// White drops the knight on e5 and Black recaptures — a position with something hanging in
    /// it, which is what the 要害 card is about.
    private static let givenAway = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "f3e5", "c6e5"]

    private static let searching = [
        Analysis(
            depth: 26,
            selectiveDepth: 34,
            lines: [
                Line(
                    score: .centipawns(38),
                    uciMoves: ["d2d4", "e5d4", "c3d4", "c5b6", "e4e5", "d7d5"],
                    san: ["d4", "exd4", "cxd4", "Bb6", "e5", "d5"]
                ),
                Line(
                    score: .centipawns(21),
                    uciMoves: ["e1g1", "d7d6", "d2d4", "c5b6", "h2h3", "e8g8"],
                    san: ["O-O", "d6", "d4", "Bb6", "h3", "O-O"]
                ),
                Line(
                    score: .centipawns(9),
                    uciMoves: ["d2d3", "d7d6", "e1g1", "a7a6"],
                    san: ["d3", "d6", "O-O", "a6"]
                ),
            ],
            nodes: 63_400_000,
            nodesPerSecond: 2_480_000,
            timeMilliseconds: 25_600
        )
    ]

    private static func opinion(
        _ score: Score, best: (uci: String, san: String)? = nil, then: [String] = []
    ) -> Analysis {
        Analysis(
            depth: 14,
            selectiveDepth: 18,
            lines: [
                Line(
                    score: score,
                    uciMoves: best.map { [$0.uci] } ?? [],
                    san: best.map { [$0.san] + then } ?? []
                )
            ],
            nodes: 4_000_000,
            nodesPerSecond: 2_000_000,
            timeMilliseconds: 2_000
        )
    }

    private func hop() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func screen(
        _ session: GameSession, engine: any Engine, opening: GameScreen.Card
    ) -> some View {
        NavigationStack {
            GameScreen(session: session, path: .constant([]), opening: opening)
        }
        .environment(EngineHost(engine))
        .environment(GameLibrary())
    }

    // ------------------------------------------------------------------ 1 · 杀

    @Test("1 · 杀 — the news, with the line numbered on the board")
    func mate() async throws {
        // Morphy's opera game before 16.Qb8+: White mates in two and Black's reply is forced.
        let game = try #require(Game(startFEN: "4kb1r/p2n1ppp/4q3/4p1B1/4P3/1Q6/PPP2PPP/2KR4 w - - 0 1"))
        let engine = ScriptedEngine(
            [],
            byPosition: [
                game.state.fen: Analysis(
                    depth: 10,
                    lines: [
                        Line(
                            score: .mate(in: 2),
                            uciMoves: ["b3b8", "d7b8", "d1d8"],
                            san: ["Qb8+", "Nxb8", "Rd8#"]
                        )
                    ]
                )
            ]
        )
        let session = GameSession.fresh(game, controllers: [.white: .hand, .black: .engine])
        session.attach(engine: engine, library: nil)
        await hop()

        let rendered = await ScreenImage.write("deck-01-mate") {
            screen(session, engine: engine, opening: .mate)
        }
        #expect(rendered.says("你有 2 步杀"))
        #expect(rendered.says("Rd8#"))
    }

    // ------------------------------------------------------------------ 2 · 战术

    @Test("2 · 战术 — one shot, named in the verbs a player declares in")
    func tactics() async throws {
        let game = try #require(Game(startFEN: "4k3/8/8/3r4/8/8/8/3QK3 w - - 0 1"))
        let engine = ScriptedEngine(
            [],
            byPosition: [
                game.state.fen: Analysis(
                    depth: 10,
                    lines: [
                        Line(score: .centipawns(500), uciMoves: ["d1d5"], san: ["Qxd5"]),
                        Line(score: .centipawns(20), uciMoves: ["e1d2"], san: ["Kd2"]),
                    ]
                )
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)

        let rendered = await ScreenImage.write("deck-02-tactics") {
            screen(session, engine: engine, opening: .tactics)
        }
        await hop()
        #expect(rendered.says("战术"))
    }

    // ------------------------------------------------------------------ 3 · 考一遍

    @Test("3 · 考一遍 — the question, answered, with all three moves side by side")
    func drill() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let asked = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6)))
        )
        let guessed = try #require(
            Game(
                startFEN: PGN.standardStartFEN,
                uciMoves: Array(Self.italian.prefix(6)) + ["d2d4"]
            )
        )
        let played = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(7)))
        )
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(
                    .centipawns(45), best: ("e1g1", "O-O"), then: ["d6", "d4"]
                ),
                guessed.state.fen: Self.opinion(.centipawns(20)),
                played.state.fen: Self.opinion(.centipawns(38)),
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 6)
        session.offer(try #require(session.viewed.state.move(matching: "d2d4")))
        session.choose(.attack)
        session.aim(at: try #require(Square("c5")))
        session.commitGuess()
        await hop()

        let rendered = await ScreenImage.write("deck-03-drill") {
            screen(session, engine: engine, opening: .drill)
        }
        #expect(rendered.says("考一遍"))
        #expect(rendered.says("d4"))
    }

    // ------------------------------------------------------------------ 4 · 这步的要害

    @Test("4 · 这步的要害 — what this move is for")
    func key() async throws {
        let (session, engine) = try await layered()
        session.commitGuess()
        await hop()

        let rendered = await ScreenImage.write("deck-04-key") {
            screen(session, engine: engine, opening: .key)
        }
        #expect(rendered.says("这步的要害"))
        #expect(!session.viewedContinuation.isEmpty, "the reveal paid for the line this reads")
    }

    /// The position right after White threw the knight away, with a Guess on the board that is not
    /// the recapture — the setup both the rings and the ranked squares are for.
    private func layered() async throws -> (GameSession, ScriptedEngine) {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.givenAway))
        let asked = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.givenAway.prefix(7)))
        )
        let guessed = try #require(
            Game(
                startFEN: PGN.standardStartFEN,
                uciMoves: Array(Self.givenAway.prefix(7)) + ["d8g5"]
            )
        )
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(.centipawns(30), best: ("d2d3", "d3")),
                guessed.state.fen: Self.opinion(
                    .centipawns(25), best: ("e5f3", "Nf3"), then: ["Qf6", "d3", "d6"]
                ),
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 7)
        session.offer(try #require(session.viewed.state.move(matching: "d8g5")))
        session.choose(.attack)
        session.aim(at: try #require(Square("e5")))
        return (session, engine)
    }

    // ------------------------------------------------------------------ 5 · 走马灯

    @Test("5 · 走马灯 — two of four plies walked, and where the whole line arrives")
    func walk() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.applyReview(
            game.plies.indices.map { ply in
                ReviewedPly(
                    score: .centipawns(20),
                    line: ply == 5 ? ["Nxe5", "Nxe5", "d4", "Bd6"] : []
                )
            },
            startEvaluation: nil,
            depth: 18
        )
        session.jump(toPly: 6)
        session.startWalk()
        session.stepWalk(by: 2)

        let rendered = await ScreenImage.write("deck-05-walk") {
            screen(session, engine: engine, opening: .walk)
        }
        #expect(rendered.says("走马灯"))
        #expect(rendered.says("第 2/4 步"))
    }

    // ------------------------------------------------------------------ 6 · 五步计划

    @Test("6 · 五步计划 — five ahead, each row saying what it is for")
    func plan() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let asked = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: ["e2e4", "e7e5"]))
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(
                    .centipawns(32), best: ("f1c4", "Bc4"),
                    then: ["Nf6", "Nf3", "Nc6", "Ng5", "d5"]
                )
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 2)

        let rendered = await ScreenImage.write("deck-06-plan") {
            screen(session, engine: engine, opening: .plan)
        }
        await hop()
        #expect(rendered.says("五步计划"))
    }

    // ------------------------------------------------------------------ 7 · 问一格

    @Test("7 · 问一格 — a square asked about, a move tried out, and the engine last")
    func scanner() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let asked = try #require(
            Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6)))
        )
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(
                    .centipawns(45), best: ("e1g1", "O-O"), then: ["d6", "d4"]
                )
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 6)
        session.armScanner()
        session.scan(at: try #require(Square("d4")))
        session.tryOut(try #require(session.scan?.arrivals.first?.move))
        session.askEngine()
        await hop()

        let rendered = await ScreenImage.write("deck-07-scanner") {
            screen(session, engine: engine, opening: .scanner)
        }
        #expect(rendered.says("问一格"))
        #expect(rendered.says("d4"))
    }

    // ------------------------------------------------------------------ 8 · 复盘

    @Test("8 · 复盘 — the pass, the move the eye is on, and the three worst")
    func review() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)
        session.applyReview(
            [
                .centipawns(30), .centipawns(25), .centipawns(35), .centipawns(30),
                .centipawns(40), .centipawns(35), .centipawns(-420), .centipawns(-410),
            ],
            startEvaluation: .centipawns(20),
            depth: 18
        )
        session.jump(toPly: 7)
        session.setPractising(false)

        let rendered = await ScreenImage.write("deck-08-review") {
            screen(
                session, engine: ScriptedEngine(Self.searching, isEndless: true), opening: .review
            )
        }
        #expect(rendered.says("复盘"))
        #expect(rendered.says("这局最贵的三步"))
    }

    // ------------------------------------------------------------------ 9 · 旁注

    @Test("9 · 旁注 — the runners-up the engine is weighing behind the move it offers")
    func reading() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .hand, .black: .engine]
        )
        session.setPractising(false)
        let engine = ScriptedEngine(Self.searching, isEndless: true)

        let rendered = await ScreenImage.write("deck-09-reading") {
            screen(session, engine: engine, opening: .reading)
        }
        #expect(rendered.says("旁注"))
        #expect(rendered.says("其它选择"))
    }

    // ------------------------------------------------------------------ 10 · 这儿还问不了的

    @Test("10 · 这儿还问不了的 — what this position cannot answer, and what would buy it")
    func missing() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game, controllers: [.white: .hand, .black: .engine])
        let engine = ScriptedEngine(Self.searching, isEndless: true)
        session.attach(engine: engine, library: nil)

        let rendered = await ScreenImage.write("deck-10-missing") {
            screen(session, engine: engine, opening: .missing)
        }
        #expect(rendered.says("这儿还问不了的"))
        #expect(rendered.says("复盘 · 最贵三步"))
    }
}
