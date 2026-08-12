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

extension PieceKind {
    var chinese: String {
        switch self {
        case .pawn: "兵"
        case .knight: "马"
        case .bishop: "象"
        case .rook: "车"
        case .queen: "后"
        case .king: "王"
        }
    }
}

extension Controller {
    var chinese: String { self == .hand ? "手动" : "引擎" }
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

/// The advantage bar: one number turned into a length.
///
/// Centipawns are unbounded and a bar is not, so the mapping has to squash. A logistic
/// curve is the honest choice — it is roughly how a score translates into a winning chance,
/// so equal-looking bars mean equally close games rather than equal pawn counts.
func advantageFraction(_ score: Score?) -> Double {
    guard let score else { return 0.5 }
    switch score {
    case .centipawns(let value):
        return 1 / (1 + pow(10, -Double(value) / 400))
    case .mate(let moves):
        return moves > 0 ? 1 : 0
    }
}

struct AdvantageBar: View {
    let score: Score?
    /// Which way up: the side at the bottom of the board fills from the bottom.
    var orientation: Orientation = .whiteAtBottom

    var body: some View {
        let white = advantageFraction(score)
        let fraction = orientation == .whiteAtBottom ? white : 1 - white
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Fixed colours rather than semantic ones: the two halves stand for white and
                // black, so they cannot follow the interface's light and dark. The outline is
                // what keeps the white half from disappearing into a light page — without it,
                // an even position looks like a bar that is only half there.
                Rectangle().fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                Rectangle()
                    .fill(Color(white: 0.97))
                    .frame(height: proxy.size.height * fraction)
            }
            .overlay(alignment: .center) {
                Rectangle().fill(Color.red.opacity(0.6)).frame(height: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.45), lineWidth: 0.5)
        )
        .frame(width: 10)
        .accessibilityLabel("优势条")
        .accessibilityValue(score?.displayText ?? "未知")
    }
}

/// A labelled row of capsules, one of which is current.
///
/// A Picker would say the same thing in less code, but these choices are the ones that stay on
/// screen for the whole game — who started, which way up the board is — and a row of capsules
/// reads as a standing fact with a way to change it, where a segmented control reads as a
/// setting being adjusted.
struct ChipPair<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var isEnabled = true
        var id: Value { value }
    }

    let title: String
    let options: [Option]
    let selection: Value
    let pick: (Value) -> Void

    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        pick(option.value)
                    } label: {
                        Text(option.label)
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                selection == option.value
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.secondary.opacity(0.14),
                                in: Capsule()
                            )
                            .opacity(option.isEnabled ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.isEnabled)
                }
            }
        }
    }
}

/// A score, coloured by who it favours.
struct ScoreLabel: View {
    let score: Score?
    var prominent = false

    var body: some View {
        Text(score?.displayText ?? "—")
            .font(prominent ? .title3.monospacedDigit().bold() : .body.monospacedDigit())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        guard let score else { return .secondary }
        return switch score {
        case .mate: .purple
        case .centipawns(let value) where value > 50: .primary
        case .centipawns(let value) where value < -50: .primary
        default: .secondary
        }
    }
}
