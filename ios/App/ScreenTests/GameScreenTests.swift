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

    /// A game under way against the engine, with the engine talking.
    @Test("the game screen shows the position, what the engine makes of it, and the moves")
    func gameInPlay() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(
            game, controllers: [.white: .hand, .black: .engine]
        )

        let rendered = await ScreenImage.write("game-in-play") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        // Whose move it is, said in that side's own bar, and what the engine says about it.
        #expect(rendered.says("白方"))
        #expect(rendered.says("该走了"))
        #expect(rendered.says("+0.38"), "the deeper snapshot should have replaced the shallow one")
        #expect(rendered.says("搜索深度 26"))
        // Three Lines, in the engine's own numerals, deepest search first.
        #expect(rendered.says("d4 exd4 cxd4 Bb6"))
        #expect(rendered.says("O-O d6 d4 Bb6"))
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
        // And the Score reached the game itself, which is what a Review will overwrite later.
        #expect(session.game.plies.last?.evaluation == .centipawns(38))
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
        #expect(rendered.says("在看第 0/8 步"))
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
        #expect(rendered.says("在看第 6/7 步"))
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
        #expect(rendered.says("白方胜"), "the bar reads the result rather than sitting half and half")
        #expect(rendered.says("1-0"), "and the number the screen has been showing resolves into it")
        #expect(rendered.says("复盘"), "with the one thing left to do said where the lines were")
        #expect(!rendered.says("和棋"))
        #expect(!rendered.says("未知"), "a finished game is not an unknown one")
        // There is nothing left to play, so the one button that plays a move is out.
        #expect(!session.canPlayBestMove)
        #expect(rendered.says("第 7 步 Qxf7#"), "the record ends where the game did")
        #expect(!rendered.says("该走了"), "and nobody is on the clock in a game that is over")
    }

    /// Practice: the engine plays on but says nothing, so the screen has to account for the
    /// number it is not showing.
    @Test("practice leaves the engine's opinion off the screen and says why")
    func practising() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession.fresh(game)
        session.setPractising(true)

        let rendered = await ScreenImage.write("game-practising") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(rendered.says("练习"))
        #expect(rendered.says("复盘"), "practice points at the one place the engine does talk")
        #expect(!rendered.says("+0.38"), "no Score anywhere while practising")
        #expect(session.analysis == nil)
    }

    // ------------------------------------------------------------------- glue

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
