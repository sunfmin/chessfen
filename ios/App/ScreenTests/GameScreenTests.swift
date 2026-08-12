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
        let session = GameSession(
            game: game,
            controllers: [.white: .hand, .black: .engine],
            origin: .fresh
        )

        let rendered = await ScreenImage.write("game-in-play") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        // Whose move it is, and what the engine says about it — the two things at the top.
        #expect(rendered.says("白方走棋"))
        #expect(rendered.says("+0.38"), "the deeper snapshot should have replaced the shallow one")
        #expect(rendered.says("深 26/34"))
        // Three Lines, in the engine's own numerals, deepest search first.
        #expect(rendered.says("d4 exd4 cxd4 Bb6"))
        #expect(rendered.says("O-O d6 d4 Bb6"))
        #expect(rendered.count(of: "+0.") >= 3)
        // The record, and the transport that walks it.
        #expect(rendered.says("Nf6"), "the notation should carry the game")
        #expect(rendered.says("上一步"))
        #expect(rendered.says("悔棋"))
        // Who plays each side, on screen rather than in a menu.
        #expect(rendered.says("白方"))
        #expect(rendered.says("黑方"))
        // And the Score reached the game itself, which is what a Review will overwrite later.
        #expect(session.game.plies.last?.evaluation == .centipawns(38))
    }

    /// A board just read off a photograph: nothing played yet, three squares the recogniser was
    /// not sure of, and the way back to the editor.
    @Test("a freshly recognised board offers the editor and rings what it was unsure of")
    func recognisedBoard() async throws {
        let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R w KQkq - 0 5"
        let game = try #require(Game(startFEN: fen))
        let session = GameSession(
            game: game,
            origin: .recognised,
            shaky: [Square("c6")!, Square("f6")!, Square("c5")!]
        )

        let rendered = await ScreenImage.write("game-recognised") {
            screen(session, engine: ScriptedEngine(Self.searching, isEndless: true))
        }

        #expect(rendered.says("拿不太准"), "the shaky squares should be counted, not hidden")
        #expect(rendered.says("改棋子"))
        #expect(rendered.says("先走"), "who starts is still open until a move is played")
        #expect(rendered.says("从这里开始走"))
    }

    /// Practice: the engine plays on but says nothing, so the screen has to account for the
    /// number it is not showing.
    @Test("practice leaves the engine's opinion off the screen and says why")
    func practising() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.italian))
        let session = GameSession(game: game, origin: .fresh)
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
