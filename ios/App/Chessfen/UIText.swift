import ChessfenKit
import SwiftUI

// The app speaks Chinese. Domain vocabulary lives in CONTEXT.md and in the package's own
// types; this is only how those things are said on screen.

extension FENIssue {
    /// Said as advice rather than as a diagnosis: the player is at the Confirm Position
    /// gate looking at a board they can fix, so each of these should name the fix.
    var chinese: String {
        switch self {
        case .malformed: "局面读不出来"
        case .badPieceCharacter: "有认不出的棋子"
        case .badRankWidth: "某一行不是 8 格"
        case .badRankCount: "不是 8 行"
        case .tooManyPieces: "棋子太多了"
        case .tooManyPawns: "兵太多了"
        case .missingKing: "缺了王，两方各要有一个"
        case .extraKing: "王多了，每方只能有一个"
        case .pawnOnBackRank: "兵不能站在第一或第八行"
        case .badSideToMove: "该谁走没说清"
        case .badCastling: "易位权写错了"
        case .castlingWithoutRook: "标了易位权，但车不在角上"
        case .castlingWithoutKing: "标了易位权，但王不在原位"
        case .badEnPassant: "吃过路兵的格子不对"
        case .badClock: "回合数不对"
        case .sideNotToMoveInCheck: "不该走的一方被将着，这个局面不可能出现"
        }
    }
}

extension Outcome {
    var chinese: String {
        switch self {
        case .ongoing: "进行中"
        case .checkmate: "将杀"
        case .stalemate: "逼和"
        case .fiftyMoveRule: "五十回合和棋"
        case .threefoldRepetition: "三次重复和棋"
        case .insufficientMaterial: "子力不足，和棋"
        }
    }
}

extension PieceColour {
    var chinese: String { self == .white ? "白方" : "黑方" }
}

extension Controller {
    var chinese: String { self == .hand ? "手动" : "引擎" }
}

extension ThinkingTime {
    /// On a chip, under a row whose title already says what the number is about.
    var chinese: String {
        switch self {
        case .mirrored: "跟着我"
        case .fixed(let seconds): "\(seconds) 秒"
        }
    }

    /// In the line that states the whole setup, where it has to stand on its own.
    var chineseSummary: String {
        switch self {
        case .mirrored: "每步跟着我"
        case .fixed(let seconds): "每步 \(seconds) 秒"
        }
    }
}

extension Game {
    /// How the game stands, in one line.
    var chineseStanding: String {
        switch state.outcome {
        case .ongoing:
            return "\(state.sideToMove.chinese)走棋\(state.inCheck ? "（被将）" : "")"
        case .checkmate:
            return "\(state.sideToMove.opposite.chinese)将杀，\(resultToken)"
        default:
            return "\(state.outcome.chinese)，\(resultToken)"
        }
    }
}

extension Game {
    /// Who is on the clock, said as a state rather than as an instruction.
    var chineseTurn: String {
        switch state.outcome {
        case .ongoing: "\(state.sideToMove.chinese)走棋"
        case .checkmate: "\(state.sideToMove.opposite.chinese)将杀"
        default: state.outcome.chinese
        }
    }
}

extension Set where Element == Square {
    /// The one line the app says about squares the camera was not sure of — nil when it
    /// was sure of every square it read. The game screen and the Confirm Position screen
    /// used to each own this line, byte for byte.
    var shakySummary: String? {
        isEmpty ? nil : "橙框那 \(count) 个格子拿不太准"
    }
}
