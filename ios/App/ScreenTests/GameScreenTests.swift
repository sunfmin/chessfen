import ChessfenKit
import SwiftUI
import Testing

@testable import Chessfen

/// The game screen, photographed.
///
/// Serialized and on the main actor because there is one screen: two of these rendering at once
/// would be two key windows, and whichever drew second would be photographing the other one.
@MainActor
@Suite(.serialized)
struct GameScreenScreenshots {
    /// The Italian, eight plies in, White to move — a position anyone who plays reads at a glance,
    /// which is what a screenshot is for.
    private static let italian = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"]

    /// One position's worth of opinion: a Score, and optionally the move the engine would play.
    /// What a study needs, as against a search that deepens.
    static func opinion(_ score: Score, best: (uci: String, san: String)? = nil) -> Analysis {
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
            nodes: 4_000_000,
            nodesPerSecond: 2_000_000,
            timeMilliseconds: 2_000
        )
    }

    /// Two Depths of the same search, because that is how one arrives: the screen is shown the
    /// shallow one and then made to replace it, exactly as it would be in someone's hand.
    private static let searching = [
        Analysis(
            depth: 18,
            selectiveDepth: 25,
            lines: [
                Line(
                    score: .centipawns(24),
                    uciMoves: ["d2d4", "e5d4", "c3d4", "c5b6"],
                    san: ["d4", "exd4", "cxd4", "Bb6"]
                ),
                Line(
                    score: .centipawns(19),
                    uciMoves: ["e1g1", "d7d6", "d2d4", "c5b6"],
                    san: ["O-O", "d6", "d4", "Bb6"]
                ),
            ],
            nodes: 9_800_000,
            nodesPerSecond: 2_360_000,
            timeMilliseconds: 4_150
        ),
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
        ),
    ]

    /// A game under way against the engine, with the engine talking — which is to say somebody
    /// has reached down and turned its opinion on, because that is not where a Game starts.
    @Test("the game screen shows the position, what the engine makes of it, and the moves")
    func gameInPlay() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .hand, .black: .engine]
        )
        session.setPractising(false)

        let rendered = await ScreenImage.write("game-in-play") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        // Whose move it is, said in that side's own bar, and what the engine says about it.
        #expect(rendered.says("白方"))
        #expect(rendered.says("该走了"))
        #expect(rendered.says("+0.38"), "the deeper snapshot should have replaced the shallow one")
        #expect(rendered.says("优势条"), "said once, at the end of the bar that draws it")
        #expect(
            !rendered.says("搜索深度"),
            "and not how fast the phone is going while it says it — that was a row of plumbing"
        )
        // How deep it has got, though, which is not the same thing: a search that stops after ten
        // seconds (docs/adr/0019) has to account for itself, or a number that stopped moving is
        // indistinguishable from an engine that died. One figure, in the strip, and no speed.
        #expect(rendered.says("深 26"))
        #expect(!rendered.says("再算"), "and no offer of more while it is still inside its Stint")
        // The move it would play, named beside the arrow the board draws — one move, because a
        // line of six is a language most people playing this have not learnt.
        #expect(rendered.says("建议 d4"))
        #expect(!rendered.says("d4 exd4 cxd4"), "and not the whole line it is the head of")
        // The other candidates, the same way: the move and what it is worth.
        #expect(rendered.says("其它选择"))
        #expect(rendered.says("O-O"))
        #expect(!rendered.says("O-O d6 d4"))
        #expect(rendered.count(of: "+0.") >= 3)
        // The record, and the whole walk through it.
        #expect(rendered.says("第 8 步 Nf6"), "the record should carry the game, move by move")
        #expect(rendered.says("开局"))
        #expect(rendered.says("上一步"))
        #expect(rendered.says("下一步"))
        #expect(rendered.says("让引擎走"), "one move from the engine, in the bar of the side to move")
        // Who plays each side, on that side's own bar, without anybody having to open anything.
        #expect(rendered.says("白方"))
        #expect(rendered.says("手动"))
        #expect(rendered.says("黑方"))
        #expect(rendered.says("引擎"))
        #expect(rendered.says("跟着我"), "and the engine's clock, where the engine is playing")
        #expect(
            !rendered.says("谁走"),
            "but the chips that change them stay folded once there are moves"
        )
        // And the Score stayed on the screen: it does *not* reach the game. A live search's
        // Depth is whatever it happened to get to, and a file that mixes those with a
        // Review's uniform ones cannot be ranked afterwards without inventing mistakes, so
        // only a Review writes an evaluation now (docs/adr/0016).
        #expect(session.game.plies.last?.evaluation == nil)
        #expect(!session.game.isReviewed)
    }

    /// A board just read off a photograph: nothing played yet, three squares the recogniser was
    /// not sure of, and the way back to the editor.
    @Test("a freshly recognised board offers the editor and rings what it was unsure of")
    func recognisedBoard() async throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R w KQkq - 0 5"
        let game = try #require(Game(startFEN: fen))
        let session = GameSession.recognised(
            game, shaky: [Square("c6")!, Square("f6")!, Square("c5")!]
        )

        let rendered = await ScreenImage.write("game-recognised") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(rendered.says("拿不太准"), "the shaky squares should be counted, not hidden")
        #expect(rendered.says("改棋子"))
        #expect(rendered.says("从这里开始走"))
        // Nothing is played yet, so the side to move has its own questions open.
        #expect(rendered.says("谁走"))
        #expect(rendered.says("手动"))
        #expect(rendered.says("先走的是白方"))
        #expect(rendered.says("翻转棋盘"))
        // Nothing to walk through yet, and the engine can be asked to open.
        #expect(rendered.says("让引擎走"))
    }

    /// A game opened again from the library, which opens where it began.
    @Test("a saved game reopens at its first position, ready to be walked forward")
    func reopenedGame() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let entry = GameLibrary.Entry(
            url: URL(filePath: "/games/chessfen-2026-08-12-190000.pgn"),
            pgn: PGN(game: game, tags: [PGN.Tag("White", "手动"), PGN.Tag("Black", "引擎")]),
            modified: Date(timeIntervalSince1970: 1_786_000_000)
        )
        let session = try #require(GameSession.opened(entry))

        let rendered = await ScreenImage.write("game-reopened") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.cursor == 0, "a reopened game opens at the position it began in")
        // Where the eye is is the record's own job — the filled card. What a browsing game needs
        // in words is the way back to the present, and that is beside the arrows that left it.
        #expect(rendered.says("回到最新"))
        #expect(rendered.says("第 1 步 e4"), "the moves are all there to be walked through")
        #expect(rendered.says("第 2 步 e5"))
        #expect(rendered.says("开局"), "including the position it began in")
    }

    /// A board just read off a photograph and then filed into a collection: the same reading, with
    /// its doubts settled by somebody keeping it.
    @Test("a filed game stops ringing the squares it once was unsure of")
    func filedBoard() async throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R w KQkq - 0 5"
        let game = try #require(Game(startFEN: fen))
        // The filed state exists only as a saved game: a reading somebody kept, with the
        // collection it was kept in written into the file.
        let entry = GameLibrary.Entry(
            url: URL(filePath: "/games/chessfen-2026-08-12-190100.pgn"),
            pgn: PGN(game: game, tags: [
                PGN.Tag(GameOrigin.tagName, GameOrigin.recognised.rawValue),
                PGN.Tag("Event", "西西里防御"),
            ]),
            modified: Date(timeIntervalSince1970: 1_786_000_100)
        )
        let session = try #require(GameSession.opened(entry))

        let rendered = await ScreenImage.write("game-filed") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.isFiled)
        #expect(session.unconfirmedSquares.isEmpty, "no rings on a board somebody has kept")
        #expect(!rendered.says("拿不太准"), "and no question about the squares under them")
        #expect(!rendered.says("改棋子"))
        // A record opens in practice, so the engine holds its opinion: no advice, no number.
        #expect(!rendered.says("+0.38"))
    }

    /// The engine on the clock. It is thinking about its own move rather than advising, and the one
    /// thing to do about that is stop waiting.
    @Test("while the engine is on the clock the screen offers to stop waiting for it")
    func engineThinking() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .engine, .black: .hand]
        )
        // The number this test is about is the engine's opinion, so it is turned on.
        session.setPractising(false)

        let rendered = await ScreenImage.write("game-engine-thinking") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.isThinking, "the engine's own turn starts the moment the screen appears")
        #expect(rendered.says("马上走"))
        #expect(rendered.says("+0.38"))
        #expect(rendered.says("白方"))
        #expect(rendered.says("引擎"))
        #expect(rendered.says("跟着我"))
        #expect(rendered.says("手动"), "and the side a person is holding says so too")
        #expect(
            !session.canPlayBestMove,
            "and 让引擎走 stands down while the engine is already walking this one"
        )
    }

    /// Ten seconds later. The advisory search has run its Stint and stopped itself, which is the
    /// whole point of a Stint (docs/adr/0019) — and the strip under the board has to say so, or a
    /// number that quietly stopped moving reads as an engine that died.
    @Test("when its Stint runs out the strip keeps the answer and offers another ten seconds")
    func adviceSpent() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .hand, .black: .engine]
        )
        session.setPractising(false)
        // The app's Stint is ten seconds. A screenshot that waited ten seconds is a screenshot
        // nobody runs, so this one is over before the screen has finished settling.
        session.adviceStint = .milliseconds(100)

        let rendered = await ScreenImage.write("game-advice-spent") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.isAdviceSpent, "the search stopped on its own rather than running on")
        #expect(rendered.says("再算 10 秒"), "and the strip offers the one thing left to do")
        #expect(rendered.says("+0.38"), "with what it found still standing")
        #expect(rendered.says("优势条"), "and the bar it found it for")
        #expect(rendered.says("建议 d4"), "the move too — stopping is not forgetting")
    }

    /// Both Controllers on the engine: the app playing itself. There is no player's last move to
    /// mirror, so the screen has to name the clock it is on — and say how to stop it.
    @Test("with both sides on the engine the screen names the clock and says how to stop")
    func selfPlay() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN))
        let session = GameSession.fresh(
            game, controllers: [.white: .engine, .black: .engine]
        )

        let rendered = await ScreenImage.write("game-self-play") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.thinkingTime == .fixed(seconds: 3), "three seconds a move until told else")
        #expect(rendered.says("白方"))
        #expect(rendered.says("黑方"))
        #expect(rendered.says("引擎"))
        // The clock, on chips, with the mirror standing down for want of anybody to mirror.
        #expect(rendered.says("每步"))
        #expect(rendered.says("3 秒"))
        #expect(rendered.says("10 秒"))
        #expect(rendered.says("跟着我"))
        #expect(rendered.says("程序自己走下去；翻回上一步就停"), "what a game with nobody in it does")
        #expect(rendered.says("马上走"), "with the way to stop waiting for the move on the clock")
    }

    /// The same game at night. Every colour on this screen has a dark half that nothing else looks
    /// at, and a palette is not checked by reading its hex values.
    @Test("the game screen holds up in the dark")
    func gameAtNight() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .hand, .black: .engine]
        )
        session.setPractising(false)

        let rendered = await ScreenImage.write("game-in-play-dark", style: .dark) {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(rendered.says("白方"))
        #expect(rendered.says("该走了"))
        #expect(rendered.says("+0.38"))
        #expect(rendered.says("让引擎走"))
    }

    /// A move played over an earlier one. The line it replaced is kept as a Variation, offered where
    /// it branches rather than lost — which is the whole reason 悔棋 is not how you go back.
    @Test("a move played over an earlier one offers the line it replaced")
    func variationKept() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)
        // Back to before 4. c3, and play something else there.
        session.step(by: -2)
        let other = try #require(session.viewed.state.legalMoves.first { $0.uci == "d2d3" })
        session.play(other)
        // And stand where the branch is, which is where the line that was replaced is offered.
        session.step(by: -1)

        let rendered = await ScreenImage.write("game-variation") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.variationsHere.count == 1, "the abandoned line is kept, not dropped")
        #expect(rendered.says("c3 Nf6"), "and offered in the notation the game is written in")
        #expect(rendered.says("回到最新"), "and the way back to the present, beside the arrows")
        #expect(rendered.says("第 7 步 d3"), "with the move that replaced it in the record")
    }

    /// A finished game. The engine has nothing to search and so says nothing, and the screen has to
    /// say who won anyway.
    @Test("a game that ended in mate reads as won, not as level")
    func matedGame() async throws {
        // 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#
        let mate = ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: mate))
        let session = GameSession.fresh(game)
        #expect(game.state.outcome == .checkmate)

        // An engine with nothing to say, which is what a real one does with a finished position.
        let rendered = await ScreenImage.write("game-mated") {
            screen(session, engine: ScriptedEngine([]))
        }

        #expect(rendered.says("白方将杀"))
        #expect(
            session.isPractising,
            "the engine was never turned on here — the result is not its opinion"
        )
        #expect(rendered.says("白方胜"), "the bar reads the result rather than sitting half and half")
        #expect(rendered.says("1-0"), "and the number the screen has been showing resolves into it")
        #expect(
            rendered.says("引擎意见"),
            "with the one thing left to do said where the lines were — a switch, not a place"
        )
        #expect(!rendered.says("和棋"))
        #expect(!rendered.says("未知"), "a finished game is not an unknown one")
        // There is nothing left to play, so the one button that plays a move is out.
        #expect(!session.canPlayBestMove)
        #expect(rendered.says("第 7 步 Qxf7#"), "the record ends where the game did")
        #expect(!rendered.says("该走了"), "and nobody is on the clock in a game that is over")
    }

    /// Practice: the engine plays on but says nothing, so the screen has to account for the
    /// number it is not showing. Nothing is switched here — this is a Game as it opens.
    @Test("practice leaves the engine's opinion off the screen and says why")
    func practising() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)

        let rendered = await ScreenImage.write("game-practising") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.isPractising, "which is where a Game starts (docs/adr/0015)")
        #expect(rendered.says("练习"))
        #expect(
            rendered.says("引擎意见"),
            "practice points at the one switch that makes the engine talk"
        )
        #expect(!rendered.says("+0.38"), "no Score anywhere while practising")
        #expect(session.analysis == nil)
    }

    /// The same game, the same engine, the same moves played into it — and nothing whispered.
    /// This is the screenshot the default is answerable to: a person reading it should not be able
    /// to work out what the engine thinks of the position, and should be in no doubt that the app
    /// is working.
    @Test("a game in play says nothing about the position until it is asked to")
    func gameInPlaySaysNothing() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game, controllers: [.white: .hand, .black: .engine])

        let rendered = await ScreenImage.write("game-in-play-silent") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        // Not one number, not one line, not one of the engine's candidates.
        #expect(!rendered.says("+0.38"))
        #expect(!rendered.says("+0.24"))
        #expect(!rendered.says("+0."), "and no Score in any of the places one goes")
        #expect(!rendered.says("d4 exd4 cxd4 Bb6"))
        #expect(!rendered.says("O-O d6 d4 Bb6"))
        #expect(!rendered.says("d3 d6 O-O a6"))
        #expect(session.analysis == nil, "nothing reached the screen to be drawn")

        // And the screen accounts for the silence rather than wearing the face of a broken engine.
        #expect(rendered.says("练习"))
        #expect(rendered.says("引擎意见"), "with the one switch that ends it, named")
        // The game itself is entirely unaffected: the moves, the clock, the engine as an opponent.
        #expect(rendered.says("第 8 步 Nf6"))
        #expect(rendered.says("该走了"))
        #expect(rendered.says("让引擎走"))
        #expect(rendered.says("引擎"), "which still plays Black")
    }

    // ------------------------------------------------------------------- the study

    /// The searches behind a reveal run in tasks of their own, so their answers are known a hop
    /// later — which is as true of the screen as it is of this test.
    private func hop() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Browsing back with the engine silent: the one board is a question now. No number anywhere,
    /// and the screen says what it wants instead of looking like a game that has lost its turn.
    @Test("a past position with the engine silent asks what you would play")
    func studyBeforeTheGuess() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)
        session.jump(toPly: 6)

        let rendered = await ScreenImage.write("game-study-asking") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(session.isStudying)
        #expect(rendered.says("你会走哪一步"))
        #expect(rendered.says("直接在棋盘上走一步"))
        #expect(!rendered.says("说不清"), "the reason is asked for after a move, not before one")
        #expect(rendered.says("第 7 步 c3"), "and the record says where the eye is")
        // The answer is not on the screen: no Score, no candidate lines, no arrow to copy.
        #expect(!rendered.says("+0."))
        #expect(!rendered.says("d4 exd4 cxd4 Bb6"))
        #expect(session.analysis == nil)
    }

    /// Committing a guess: your move, the engine's, and the one actually played, at one Depth.
    @Test("committing a guess shows it against the engine's move and the one that was played")
    func studyAfterTheReveal() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let asked = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6))))
        let guessed = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6)) + ["d2d4"]))
        let played = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(7))))
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(.centipawns(45), best: ("e1g1", "O-O")),
                guessed.state.fen: Self.opinion(.centipawns(20)),
                played.state.fen: Self.opinion(.centipawns(38)),
            ]
        )

        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 6)
        let d4 = try #require(session.viewed.state.move(matching: "d2d4"))
        session.offer(d4)
        // One tap for the verb, one for the target — and the reason is committed with the move,
        // not after seeing what the move was worth.
        session.choose(.attack)
        session.aim(at: try #require(Square("c5")))
        session.commitGuess()
        await hop()

        let rendered = await ScreenImage.write("game-study-revealed") {
            screen(session, engine: engine)
        }

        let reveal = try #require(session.reveal)
        #expect(reveal.lost == 25)
        #expect(reveal.counts == true)
        // Three moves, three numbers, and no combined score anywhere.
        #expect(rendered.says("你走"))
        #expect(rendered.says("d4"))
        #expect(rendered.says("引擎"))
        #expect(rendered.says("O-O"))
        #expect(rendered.says("实战"))
        #expect(rendered.says("c3"))
        #expect(rendered.says("过关"), "and what it was worth, in words")
        #expect(rendered.says("深度 14"), "with the Depth all three were computed at named")
        #expect(rendered.says("改走这步"), "a guess worth playing can be played")
        // The second verdict, beside the first and never multiplied into it.
        #expect(rendered.says("攻 c5"))
        #expect(rendered.says("说对了"))
        #expect(rendered.says("走对了，理由也站得住"))
        #expect(session.reveal?.intentCheck?.verdict == .held)
        // The guess is on the board and not in the game: the record still ends where it did.
        #expect(session.game.plies.map(\.san).last == "Nf6")
        #expect(rendered.says("第 8 步 Nf6"))
    }

    /// The reason is asked for before anything is shown, and the two verdicts are marked
    /// separately: this is the screenshot for "right move, wrong reason", which is the failure no
    /// other chess app can see.
    @Test("a good move given for a reason that is not true reads as exactly that")
    func studyRightMoveWrongReason() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let asked = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6))))
        let guessed = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Array(Self.italian.prefix(6)) + ["d2d4"]))
        let engine = ScriptedEngine(
            Self.searching,
            isEndless: true,
            byPosition: [
                asked.state.fen: Self.opinion(.centipawns(45), best: ("e1g1", "O-O")),
                guessed.state.fen: Self.opinion(.centipawns(20)),
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        session.jump(toPly: 6)

        session.offer(try #require(session.viewed.state.move(matching: "d2d4")))
        // 吃 d4 — "I win something here" about a quiet move, which is the commonest wrong reason
        // there is and one the rules code can settle in microseconds.
        session.choose(.take)
        session.aim(at: try #require(Square("d4")))
        session.commitGuess()
        await hop()

        let marked = await ScreenImage.write("game-study-wrong-reason") {
            screen(session, engine: engine)
        }

        let reveal = try #require(session.reveal)
        #expect(reveal.counts == true)
        #expect(reveal.intentCheck?.verdict == .failed)
        #expect(marked.says("这步棋没问题，但理由不成立"))
        #expect(marked.says("吃 d4"))
        #expect(marked.says("没做到"))
        #expect(marked.says("没有在 d4 吃子"), "with the fact about the board that settles it")
        // And it is written into the game whether it held or not.
        #expect(
            session.game.variations(atPly: 6).first?.first?.intent
                == .claim(.take, try #require(Square("d4")))
        )
    }

    // ------------------------------------------------------------------- the layers

    /// A game with something actually hanging in it, so the rings have something to ring: after
    /// 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. Nxe5?? Nxe5 White has thrown a knight away.
    private static let givenAway = [
        "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "f3e5", "c6e5",
    ]

    /// Both board layers at once, with the two arrows: the engine's teal and the player's violet,
    /// on a position that has already been played into.
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
                guessed.state.fen: Self.opinion(.centipawns(25)),
            ]
        )
        let session = GameSession.fresh(game)
        session.attach(engine: engine, library: nil)
        // The position right after White threw the knight away: it stands on e5 attacked by the
        // knight on c6 and defended by nothing, which is exactly what the red ring is for. Black
        // is to move, and the guess on the board is not the recapture that was played.
        session.jump(toPly: 7)
        session.offer(try #require(session.viewed.state.move(matching: "d8g5")))
        session.choose(.attack)
        session.aim(at: try #require(Square("e5")))
        session.setShowsControlChange(true)
        return (session, engine)
    }

    @Test("a studied position rings what is hanging and shows what the move changed")
    func boardLayers() async throws {
        let (session, engine) = try await layered()

        let rendered = await ScreenImage.write("game-layers") {
            screen(session, engine: engine)
        }

        // The layers are on the board, which is a drawing — so what is asserted here is the state
        // the drawing is made from, and the PNG is the record of how it looked.
        let loose = try #require(session.viewed.loosePieces)
        #expect(loose.contains(try #require(Square("e5"))), "the knight White left there")
        #expect(session.showsControlChange)
        let change = try #require(session.viewed.lastMoveControlChange)
        #expect(!change.isEmpty)
        #expect(session.guess?.san == "Qg5", "the player's own arrow has something to draw")
        #expect(session.declaredIntent?.target == Square("e5"), "and the claim has a target to ring")
        #expect(rendered.says("这步改了什么"))
        #expect(rendered.says("红圈"), "with the one mark that needs a word said in one")
        // And the layer's own words, which it went without for far too long: a wash on nine
        // squares in one colour is a thing nobody can read, so the two directions are told apart
        // and both are named, in the name of the side whose move it was.
        #expect(rendered.says("管住了"), "what the move took a grip on")
        #expect(rendered.says("松开了"), "and what it let go of, which is the half that was missing")
        #expect(rendered.says("\(change.gained.count) 格"))
        #expect(rendered.says("\(change.lost.count) 格"))
    }

    @Test("the same two layers hold up in the dark")
    func boardLayersInTheDark() async throws {
        let (session, engine) = try await layered()

        let rendered = await ScreenImage.write("game-layers-dark", style: .dark) {
            screen(session, engine: engine)
        }

        #expect(rendered.says("这步改了什么"))
        #expect(rendered.says("你走 Qg5"))
        #expect(rendered.says("攻 e5"), "the claim, in the player's own words")
    }

    @Test("neither layer appears on the position the player is about to move in")
    func noLayersOnTheLivePosition() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.givenAway))
        let session = GameSession.fresh(game)
        session.setShowsControlChange(true)

        // There is plenty hanging in this position — that is the point of the fixture — and the
        // board says none of it, because the next move is the player's to find.
        #expect(try #require(session.viewed.loosePieces).isEmpty == false)

        let silent = await ScreenImage.write("game-layers-live") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }
        #expect(!silent.says("这步改了什么"), "the control layer is not even offered here")
        #expect(!silent.says("红圈"))

        // And with the engine's opinion on it is still not offered: the gate is the position, not
        // the switch.
        session.setPractising(false)
        let talking = await ScreenImage.write("game-layers-live") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }
        #expect(!talking.says("这步改了什么"))
        #expect(!talking.says("红圈"))
    }

    /// The switch on: this is 复盘, on the board the game was played on.
    @Test("turning the engine's opinion on puts the whole game's report on the same screen")
    func reportWithTheSwitchOn() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)
        // A pass that has already run: the curve, the labels and the Depth are what it left.
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

        let rendered = await ScreenImage.write("game-report") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(!session.isPractising)
        #expect(session.reviewPass == nil, "a Game that already has a pass is not made to sit through another")
        #expect(rendered.says("优势条"), "the bar is back, because the opinion is on")
        #expect(rendered.says("第 4 回合 白方 c3"), "the move the eye is on")
        #expect(rendered.says("漏着"), "what the pass made of it")
        #expect(rendered.says("-4.20"), "and its Score")
        #expect(rendered.says("深度 18"), "named, because a Score without one compares to nothing")
        #expect(
            !rendered.says("按深度 18 算的"),
            "but as two words beside the number, not a sentence on a row of its own"
        )
        #expect(rendered.says("这局最贵的三步"), "with the worst moves offered as the questions they are")
        // And no separate destination for any of it.
        #expect(!rendered.says("复盘"))
    }

    /// The curve behind the moves: one strip, the record still the record, the shape of the game
    /// underneath it.
    @Test("the curve is the ground the record stands on, not a second record")
    func theCurveIsAGround() async throws {
        let session = try Self.reviewed()

        let rendered = await ScreenImage.write("game-report") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(rendered.says("第 7 步 c3"), "the moves read exactly as they did")
        #expect(rendered.says("第 8 步 Nf6"))
        #expect(rendered.says("开局"), "including the way back to the start")
        #expect(rendered.says("分数曲线"), "and the curve is behind them")
        #expect(rendered.says("第 4 回合 白方 c3"), "what a curve cannot say is said under it")
        #expect(rendered.says("深度 18"))
    }

    @Test("a practising board has no curve behind its record, and nor has an unscored game")
    func theCurveIsTheEnginesVoice() async throws {
        let practising = try Self.reviewed()
        practising.setPractising(true)
        let quiet = await ScreenImage.write("game-record-practising") {
            screen(practising, engine: ScriptedEngine(Self.searching, isEndless: true))
        }
        #expect(!quiet.says("分数曲线"), "a curve is a Score, and practice is not being told one")
        #expect(quiet.says("第 7 步 c3"), "the record itself is unchanged by any of this")

        let unscored = GameSession.fresh(
            try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        )
        unscored.setPractising(false)
        let blank = await ScreenImage.write("game-record-unscored") {
            screen(unscored, engine: ScriptedEngine(Self.searching, isEndless: true))
        }
        #expect(!blank.says("分数曲线"), "nothing to draw one out of yet")
        #expect(blank.says("这局还没打过分"))
    }

    // ------------------------------------------------------------------- glue

    /// The Italian eight plies in, with a pass already over it and the switch on — the state both
    /// pictures of the record are read in.
    @MainActor
    private static func reviewed() throws -> GameSession {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: italian))
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
        return session
    }

    /// The screen as the app pushes it: inside a navigation stack, with the engine and the library
    /// in the environment. The engine is the only thing that is not the app's own.
    private func screen(_ session: GameSession, engine: any Engine) -> some View {
        NavigationStack {
            GameScreen(session: session, path: .constant([]))
        }
        .environment(EngineHost(engine))
        .environment(GameLibrary())
    }
}

/// The one thing this screen promises: the board does not move.
///
/// Everything around it changes every single move — whose bar is live, which side the engine is
/// answering for, what it is answering — and the board is what a person is looking at while it
/// does. A bar that grew by a line when its side came on the clock walked the board up and down
/// the screen once per ply, which is unusable and was invisible to every test that only read
/// words. So this one reads pixels.
@MainActor
@Suite(.serialized)
struct BoardStandsStill {
    private static let italian = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"]

    private static let searching = [
        Analysis(
            depth: 24,
            selectiveDepth: 31,
            lines: [
                Line(
                    score: .centipawns(31),
                    uciMoves: ["d2d4", "e5d4"],
                    san: ["d4", "exd4"]
                )
            ],
            nodes: 50_000_000,
            nodesPerSecond: 2_400_000,
            timeMilliseconds: 20_000
        )
    ]

    @Test("the board sits in the same place whichever colour is on the clock")
    func boardDoesNotWalk() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))

        // The same game one ply apart: White to move, then Black to move. Nothing else differs.
        let white = GameSession.fresh(game)
        let whiteShot = await shoot("game-steady-white", white)

        let black = GameSession.fresh(game)
        black.step(by: -1)
        let blackShot = await shoot("game-steady-black", black)

        #expect(white.viewed.state.sideToMove == .white)
        #expect(black.viewed.state.sideToMove == .black)

        let onWhite = try #require(boardEdges(of: whiteShot.url))
        let onBlack = try #require(boardEdges(of: blackShot.url))
        // A pixel, not a point: at three pixels to the point that is the hairline above the board
        // landing either side of a boundary, and no eye has ever seen it. A ply's worth of bar is
        // seventy-five.
        #expect(
            abs(onWhite.lowerBound - onBlack.lowerBound) <= 1,
            "the board's top moved between plies: \(onWhite) then \(onBlack)"
        )
        #expect(
            abs(onWhite.count - onBlack.count) <= 1,
            "the board changed size between plies: \(onWhite) then \(onBlack)"
        )
    }

    // ------------------------------------------------------------------- glue

    private func shoot(_ name: String, _ session: GameSession) async -> ScreenImage.Rendered {
        await ScreenImage.write(name) {
            NavigationStack {
                GameScreen(session: session, path: .constant([]))
            }
            .environment(EngineHost(ScriptedEngine(Self.searching, isEndless: true)))
            .environment(GameLibrary())
        }
    }

    /// The rows down the middle of the picture that the board occupies.
    ///
    /// Told apart by colour: the squares are saturated wood (a red end and a dim blue end), and
    /// everything else on this screen — parchment, the white half of the advantage bar, teal,
    /// ink — fails one of the two. The longest run of them rather than the outermost, because a
    /// stray antialiased pixel somewhere up in the bars would otherwise pass for the board's edge.
    private func boardEdges(of url: URL) -> ClosedRange<Int>? {
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let column = width / 2
        var longest: ClosedRange<Int>?
        var start: Int?
        for row in 0...height {
            let isBoard: Bool
            if row == height {
                isBoard = false
            } else {
                let offset = (row * width + column) * 4
                isBoard = Int(pixels[offset]) > 0xB0 && Int(pixels[offset + 2]) < 0xC0
            }
            switch (isBoard, start) {
            case (true, nil):
                start = row
            case (false, .some(let from)):
                let run = from...(row - 1)
                if run.count > (longest?.count ?? 0) { longest = run }
                start = nil
            default:
                break
            }
        }
        return longest
    }
}
