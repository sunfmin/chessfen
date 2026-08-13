import ChessfenKit
import Foundation
import Testing

/// What a saved record opens facing: the side about to move, whoever that is.

@MainActor @Test("a saved record opens facing the side to move")
func savedRecordFacesSideToMove() throws {
    // Black to move at the start: the board must turn around for it.
    let blackToMove = try #require(
        Game(startFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")
    )
    let entry = GameLibrary.Entry(
        url: URL(filePath: "/games/chessfen-black-to-move.pgn"),
        pgn: PGN(game: blackToMove, tags: [PGN.Tag(GameOrigin.tagName, GameOrigin.recognised.rawValue)]),
        modified: Date(timeIntervalSince1970: 1_786_000_000)
    )
    #expect(try #require(GameSession.opened(entry)).orientation == .blackAtBottom)

    // And the usual case: a game that began with White to move opens white at the bottom.
    let standard = try #require(Game(startFEN: PGN.standardStartFEN))
    let standardEntry = GameLibrary.Entry(
        url: URL(filePath: "/games/chessfen-standard.pgn"),
        pgn: PGN(game: standard, tags: []),
        modified: Date(timeIntervalSince1970: 1_786_000_100)
    )
    #expect(try #require(GameSession.opened(standardEntry)).orientation == .whiteAtBottom)
}
