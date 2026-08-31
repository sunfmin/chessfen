import ChessfenKit
import SwiftUI
import Testing
import UIKit

@testable import Chessfen

/// PROTOTYPE — the three layouts of GameScreenPrototype.swift, photographed so they can be
/// flipped through without a device. Goes when that file does.
///
/// The question these answer: each colour's controls on that colour's own side of the board,
/// and the record as a chess.com-style single line you scroll, with arrows, tap-to-rewind.
@MainActor
@Suite(.serialized)
struct GameScreenPrototypeScreenshots {
    /// Morphy's opera game as far as 11. Bxb5 — twenty plies, which is more than fits in one
    /// line on a phone. A record that fits is not a test of a record you scroll.
    private static let opera = [
        "e2e4", "e7e5", "g1f3", "d7d6", "d2d4", "c8g4", "d4e5", "g4f3", "d1f3", "d6e5",
        "f1c4", "g8f6", "f3b3", "d8e7", "b1c3", "c7c6", "c1g5", "b7b5", "c3b5", "c6b5",
    ]

    private static let searching = [
        Analysis(
            depth: 22,
            selectiveDepth: 30,
            lines: [
                Line(
                    score: .centipawns(112),
                    uciMoves: ["c4b5", "b8d7", "e1c1", "a8d8"],
                    san: ["Bxb5+", "Nbd7", "O-O-O", "Rd8"]
                ),
                Line(
                    score: .centipawns(74),
                    uciMoves: ["b5c4", "b8d7", "e1g1"],
                    san: ["Bc4", "Nbd7", "O-O"]
                ),
            ],
            nodes: 41_000_000,
            nodesPerSecond: 2_410_000,
            timeMilliseconds: 17_000
        )
    ]

    private func shoot(
        _ name: String,
        variant: PrototypeVariant,
        style: UIUserInterfaceStyle = .light,
        _ session: GameSession
    ) async -> ScreenImage.Rendered {
        await ScreenImage.write(name, style: style) {
            NavigationStack {
                PrototypeGameScreen(session: session, variant: variant)
            }
            .environment(EngineHost(ScriptedEngine(Self.searching, isEndless: true)))
            .environment(GameLibrary())
        }
    }

    private func inPlay() throws -> GameSession {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.opera))
        return GameSession.fresh(game, controllers: [.white: .hand, .black: .engine])
    }

    // ------------------------------------------------------------------ A

    @Test("A — two player bars sandwich the board")
    func variantA() async throws {
        let rendered = await shoot("prototype-A-in-play", variant: .a, try inPlay())
        #expect(rendered.says("白方"))
        #expect(rendered.says("黑方"))
        #expect(rendered.says("让引擎走"))
    }

    /// The point of the whole layout: turn the board round and the controls go with it. Black
    /// is at the bottom here, so Black's bar is the near one.
    @Test("A — flipping the board moves each side's controls to its own side")
    func variantAFlipped() async throws {
        let session = try inPlay()
        session.orientation = .blackAtBottom
        let rendered = await shoot("prototype-A-flipped", variant: .a, session)
        #expect(rendered.says("翻转棋盘"))
    }

    @Test("A — at night")
    func variantADark() async throws {
        _ = await shoot("prototype-A-dark", variant: .a, style: .dark, try inPlay())
    }

    // ------------------------------------------------------------------ B

    @Test("B — the bars are hairlines on the board's own edges")
    func variantB() async throws {
        let rendered = await shoot("prototype-B-in-play", variant: .b, try inPlay())
        #expect(rendered.says("让引擎走"))
    }

    /// Rewound seven plies: the strip has to say where the eye is without moving the board.
    @Test("B — browsing back marks the move being looked at in the strip")
    func variantBBrowsing() async throws {
        let session = try inPlay()
        session.step(by: -7)
        let rendered = await shoot("prototype-B-browsing", variant: .b, session)
        #expect(session.cursor == 13)
        #expect(rendered.says("Bxf3") || rendered.says("Nf6"))
    }

    // ------------------------------------------------------------------ C

    @Test("C — the side on the clock holds the controls")
    func variantC() async throws {
        let rendered = await shoot("prototype-C-in-play", variant: .c, try inPlay())
        #expect(rendered.says("让引擎走"))
    }

    /// With the engine on White's clock the action in White's bar is 马上走 rather than
    /// 让引擎走 — which is the variant's whole claim: the bar belongs to whoever is to move.
    @Test("C — with the engine on the clock the near bar offers to stop waiting")
    func variantCEngineTurn() async throws {
        let game = try #require(Game(startFEN: PGN.standardStartFEN, uciMoves: Self.opera))
        let session = GameSession.fresh(game, controllers: [.white: .engine, .black: .hand])
        let rendered = await shoot("prototype-C-engine-turn", variant: .c, session)
        #expect(rendered.says("马上走"))
    }

    /// One side's options unfolded, which is where the chips went.
    @Test("C — a bar unfolds into that side's own options")
    func variantCUnfolded() async throws {
        let session = try inPlay()
        let rendered = await ScreenImage.write("prototype-C-unfolded") {
            NavigationStack {
                PrototypeGameScreen(session: session, variant: .c, unfolded: .white)
            }
            .environment(EngineHost(ScriptedEngine(Self.searching, isEndless: true)))
            .environment(GameLibrary())
        }
        #expect(rendered.says("手动"))
        #expect(rendered.says("引擎"))
    }
}
