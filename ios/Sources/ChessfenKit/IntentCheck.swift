/// Whether a declared Intent actually held, and why not when it did not.
///
/// The second of a Drill's two verdicts, and kept apart from the first on purpose: "right move,
/// wrong reason" and "wrong move, right reason" are different failures with different remedies,
/// and multiplying them into one number is how an app ends up saying nothing (docs/adr/0018).
public struct IntentCheck: Hashable, Sendable {
    public enum Verdict: Hashable, Sendable {
        /// The claim is true of the position the move made.
        case held
        /// The claim is not true. `note` says what the board says instead.
        case failed
        /// 说不清 — no claim was made, so there is nothing to be right or wrong about.
        case noClaim
    }

    public let verdict: Verdict
    /// One short sentence about the board, in the same terms the claim was made in. The teaching
    /// is here: "f7 的守子没有增加" is a fact a player can go and look at, where "错" is not.
    public let note: String?

    public var held: Bool { verdict == .held }
}

extension Intent {
    /// Checks this Intent against the position `move` makes.
    ///
    /// Nil when it could not be checked at all — an unreadable position, an illegal move. Not
    /// `.failed`: an app that cannot tell has no business saying somebody was wrong.
    public func check(_ move: Move, in before: Game) -> IntentCheck? {
        guard case .claim(let verb, let target) = self else {
            return IntentCheck(verdict: .noClaim, note: nil)
        }

        let mover = before.state.sideToMove
        let opponent = mover.opposite
        var after = before
        guard after.apply(move),
            let beforeControl = Rules.control(startFEN: before.startFEN, moves: before.uciMoves),
            let afterControl = Rules.control(startFEN: after.startFEN, moves: after.uciMoves),
            let beforePieces = BoardRenderer.placement(before.state.fen),
            let afterPieces = BoardRenderer.placement(after.state.fen)
        else { return nil }

        func held(_ note: String) -> IntentCheck { IntentCheck(verdict: .held, note: note) }
        func failed(_ note: String) -> IntentCheck { IntentCheck(verdict: .failed, note: note) }

        /// Where the piece was actually taken from — not the destination, for en passant.
        let captured =
            move.isEnPassant ? Square(file: move.to.file, rank: move.from.rank) : move.to
        let exchange = Rules.exchangeValue(
            startFEN: before.startFEN, moves: before.uciMoves, uci: move.uci
        )

        switch verb {
        // 吃 — "I win material here". Not "this is a capture", which no player could get wrong
        // and which would therefore teach nothing.
        case .take:
            guard move.isCapture, captured == target else {
                return failed("这一步没有在 \(target) 吃子")
            }
            guard let exchange else { return nil }
            return exchange == .winning
                ? held("在 \(target) 吃子赢了子")
                : failed("\(target) 上的交换不赚：对方吃回来不亏")

        // 换 — "a trade that does not lose". The pair 吃/换 is the one players confuse most, and
        // the exchange value is exactly what tells them apart.
        case .trade:
            guard move.isCapture, captured == target else {
                return failed("这一步没有在 \(target) 换子")
            }
            guard let exchange else { return nil }
            return exchange == .losing
                ? failed("\(target) 上这个换子是亏的")
                : held("\(target) 上换得起")

        // 攻 — "I now threaten that piece, and it cannot hold". Two halves, both falsifiable:
        // the threat has to be new, and it has to outnumber the defence.
        case .attack:
            guard let piece = afterPieces[target], piece.colour == opponent else {
                return failed("\(target) 上没有对方的子")
            }
            let now = afterControl.attackers(of: target, by: mover)
            let was = beforeControl.attackers(of: target, by: mover)
            guard now > was else {
                return failed("\(target) 上的子并没有因为这一步多受一次攻击")
            }
            guard now > afterControl.attackers(of: target, by: opponent) else {
                return failed("\(target) 对方守得住：\(now) 攻 \(afterControl.attackers(of: target, by: opponent)) 守")
            }
            return held("\(target) 上的子挨打了，而且守不住")

        // 护 — "it now has one more defender". Purely a statement about the control map, which is
        // why it is the easiest of the eight to check and the easiest to be wrong about.
        case .defend:
            let now = afterControl.attackers(of: target, by: mover)
            let was = beforeControl.attackers(of: target, by: mover)
            return now > was
                ? held("\(target) 的守子从 \(was) 变成 \(now)")
                : failed("\(target) 的守子没有增加，还是 \(was)")

        // 躲 — "this piece was hanging, and where it went it is not". The target is the attacker
        // it ran from, so the claim names both ends of it.
        case .flee:
            guard let attacker = beforePieces[target], attacker.colour == opponent else {
                return failed("\(target) 上原本没有对方的子")
            }
            let attacked = beforeControl.attackers(of: move.from, by: opponent)
            let defended = beforeControl.attackers(of: move.from, by: mover)
            guard attacked > defended else {
                return failed("\(move.from) 本来不算悬着：\(attacked) 攻 \(defended) 守")
            }
            guard let exchange else { return nil }
            return exchange == .losing
                ? failed("走到 \(move.to) 一样会被吃")
                : held("从 \(move.from) 躲开了 \(target)")

        // 挡 — "I interposed on a line". Geometry and nothing else: something of the mover's,
        // in line with the square stepped onto, is attacked less than it was.
        case .block:
            guard move.to == target else {
                return failed("这一步没有走到 \(target)")
            }
            let relieved = (0..<64).compactMap(Square.init(index:)).first { square in
                square != target
                    && afterPieces[square]?.colour == mover
                    && Self.inLine(target, square)
                    && afterControl.attackers(of: square, by: opponent)
                        < beforeControl.attackers(of: square, by: opponent)
            }
            guard let relieved else {
                return failed("走到 \(target) 没有挡住什么")
            }
            return held("挡在 \(target)，\(relieved) 上的子不再挨那一击")

        // 占 — "I hold this square more than the opponent does". Before against after, so holding
        // a square you already held is not a claim.
        case .hold:
            guard afterControl.holder(of: target) == mover else {
                let mine = afterControl.attackers(of: target, by: mover)
                let theirs = afterControl.attackers(of: target, by: opponent)
                return failed("\(target) 还算不上你的：\(mine) 对 \(theirs)")
            }
            let now =
                afterControl.attackers(of: target, by: mover)
                - afterControl.attackers(of: target, by: opponent)
            let was =
                beforeControl.attackers(of: target, by: mover)
                - beforeControl.attackers(of: target, by: opponent)
            return now > was
                ? held("\(target) 的争夺从 \(was) 变成 \(now)，归你了")
                : failed("\(target) 本来就归你，这一步没有改变什么")
        }
    }

    /// Whether two squares share a rank, a file or a diagonal — the three ways a piece can stand
    /// between two others.
    private static func inLine(_ one: Square, _ other: Square) -> Bool {
        one.file == other.file || one.rank == other.rank
            || abs(one.file - other.file) == abs(one.rank - other.rank)
    }
}
