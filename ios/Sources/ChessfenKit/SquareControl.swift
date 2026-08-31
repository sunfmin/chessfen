import CStockfish

/// Who attacks each of the 64 squares, per colour.
///
/// The map a move's purpose is made of. "Defended" and "hanging" and "this square is mine"
/// are all statements about this and nothing else, so every screen and every check that
/// needs one of them asks here rather than counting pieces its own way.
///
/// A piece standing on a square does not attack it. Pinned pieces do count: a pinned
/// defender still answers a capture on the square it covers, because the recapture happens
/// before the pin could ever be cashed.
public struct SquareControl: Hashable, Sendable {
    /// Attacker counts by square index, 0...63.
    private let white: [Int]
    private let black: [Int]

    init(white: [Int], black: [Int]) {
        precondition(white.count == 64 && black.count == 64)
        self.white = white
        self.black = black
    }

    public func attackers(of square: Square, by colour: PieceColour) -> Int {
        colour == .white ? white[square.index] : black[square.index]
    }

    /// Which colour attacks this square more often, or nil when they are level — including
    /// level at nothing, which is much the commonest case.
    public func holder(of square: Square) -> PieceColour? {
        let mine = white[square.index]
        let theirs = black[square.index]
        if mine == theirs { return nil }
        return mine > theirs ? .white : .black
    }

    /// The squares where this map and another disagree about who holds them — what a move
    /// changed, when the two maps are the positions either side of it.
    public func squaresDiffering(from other: SquareControl) -> Set<Square> {
        var changed: Set<Square> = []
        for index in 0..<64 {
            guard let square = Square(index: index) else { continue }
            if holder(of: square) != other.holder(of: square) { changed.insert(square) }
        }
        return changed
    }
}

/// What a move is worth in material once both sides have taken everything worth taking on
/// the square it lands on.
///
/// The difference between 吃 and 换 — "I win a piece here" against "this is an even trade" —
/// which is the pair a player confuses most often. For a quiet move it answers a different
/// and just as useful question: whether the piece is walking somewhere it can simply be
/// taken.
public enum ExchangeValue: Hashable, Sendable {
    case losing
    case level
    case winning
}

extension Rules {
    /// The control map of the position `moves` leads to, or nil if the FEN fails validation
    /// or some move is not legal where it is played.
    public static func control(startFEN: String, moves: [String] = []) -> SquareControl? {
        withCStrings(moves) { pointers in
            var raw = CfControl()
            guard cf_square_control(startFEN, pointers, Int32(moves.count), &raw) else {
                return nil
            }
            return SquareControl(
                white: counts(of: raw.white),
                black: counts(of: raw.black)
            )
        }
    }

    /// What `uci` is worth in material in the position `moves` leads to. Nil when the
    /// position does not validate or the move is not legal in it.
    public static func exchangeValue(
        startFEN: String, moves: [String] = [], uci: String
    ) -> ExchangeValue? {
        withCStrings(moves) { pointers in
            var raw = Int32(0)
            guard cf_exchange_value(startFEN, pointers, Int32(moves.count), uci, &raw) else {
                return nil
            }
            switch raw {
            case Int32(CF_EXCHANGE_WINNING.rawValue): return .winning
            case Int32(CF_EXCHANGE_LOSING.rawValue): return .losing
            default: return .level
            }
        }
    }

    /// A fixed-size C array of 64 counts as a Swift array. Imported as a tuple, so the
    /// bytes are read rather than the tuple walked — the same way a FEN verdict's squares are.
    private static func counts(of raw: some Any) -> [Int] {
        withUnsafeBytes(of: raw) { bytes in
            bytes.bindMemory(to: Int32.self).map(Int.init)
        }
    }
}
