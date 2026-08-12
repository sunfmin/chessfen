import Foundation

/// The stored form of a Game, which is also its exported form and its imported form —
/// there is deliberately only one (docs/adr/0010). `[FEN]` carries the recognised
/// starting Position and `{[%eval …]}` carries a Review's scores, both being conventions
/// PGN already has.
public struct PGN: Hashable, Sendable {
    /// Tag pairs in the order they will be written. PGN wants the seven-tag roster first.
    public var tags: [Tag]
    public var game: Game

    public struct Tag: Hashable, Sendable {
        public let name: String
        public var value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public static let standardStartFEN =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private static let rosterOrder = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]

    public init(game: Game, tags: [Tag] = []) {
        self.game = game
        self.tags = tags
    }

    public func tag(_ name: String) -> String? {
        tags.first { $0.name == name }?.value
    }

    // ------------------------------------------------------------------ writing

    public var text: String {
        var lines: [String] = []

        var written = Set<String>()
        var roster = tags
        for name in Self.rosterOrder {
            let value = roster.first { $0.name == name }?.value ?? Self.rosterDefault(name, game)
            lines.append("[\(name) \"\(Self.escaped(value))\"]")
            written.insert(name)
        }
        if game.startFEN != Self.standardStartFEN {
            lines.append("[SetUp \"1\"]")
            lines.append("[FEN \"\(game.startFEN)\"]")
            written.formUnion(["SetUp", "FEN"])
        }
        roster.removeAll { written.contains($0.name) }
        for tag in roster {
            lines.append("[\(tag.name) \"\(Self.escaped(tag.value))\"]")
        }

        lines.append("")
        lines.append(contentsOf: Self.wrap(movetextTokens, at: 80))
        return lines.joined(separator: "\n") + "\n"
    }

    private var movetextTokens: [String] {
        // A Game recognised from a picture usually starts mid-game, and may start with
        // black to move — in which case PGN wants "12... Nf6" before the first white move.
        let moveNumber = Int(game.startFEN.split(separator: " ").last.flatMap { Int($0) } ?? 1)
        let sideToMove: PieceColour =
            game.startFEN.split(separator: " ").dropFirst().first == "b" ? .black : .white
        return Self.tokens(for: game.plies, from: moveNumber, sideToMove: sideToMove)
            + [game.resultToken]
    }

    /// One line of moves, with its Variations in brackets after the moves they replace —
    /// which is where PGN has always put them, and why a game written here opens in anything
    /// else with its branches intact.
    private static func tokens(
        for plies: [Game.Ply], from moveNumber: Int, sideToMove: PieceColour
    ) -> [String] {
        var written: [String] = []
        var moveNumber = moveNumber
        var sideToMove = sideToMove

        for (index, ply) in plies.enumerated() {
            if sideToMove == .white {
                written.append("\(moveNumber).")
            } else if index == 0 {
                written.append("\(moveNumber)...")
            }
            written.append(ply.san)
            if let evaluation = ply.evaluation {
                written.append("{[%eval \(evaluation.pgnText)]}")
            }
            for variation in ply.variations {
                // A Variation stands in for this move, so it is numbered as this move.
                var inner = tokens(for: variation, from: moveNumber, sideToMove: sideToMove)
                guard !inner.isEmpty else { continue }
                inner[0] = "(" + inner[0]
                inner[inner.count - 1] += ")"
                written.append(contentsOf: inner)
            }
            if sideToMove == .black { moveNumber += 1 }
            sideToMove = sideToMove.opposite
        }
        return written
    }

    private static func rosterDefault(_ name: String, _ game: Game) -> String {
        switch name {
        case "Event": "chessfen"
        case "Site": "chessfen"
        case "Date": "????.??.??"
        case "Round": "-"
        case "White": "?"
        case "Black": "?"
        case "Result": game.resultToken
        default: "?"
        }
    }

    private static func escaped(_ value: String) -> String {
        String(value.flatMap { character -> [Character] in
            character == "\"" || character == "\\" ? ["\\", character] : [character]
        })
    }

    private static func wrap(_ tokens: [String], at width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for token in tokens {
            if line.isEmpty {
                line = token
            } else if line.count + 1 + token.count <= width {
                line += " " + token
            } else {
                lines.append(line)
                line = token
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// Today in PGN's `YYYY.MM.DD`.
    public static func dateTag(_ date: Date = Date(), calendar: Calendar = .current) -> Tag {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = String(
            format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        return Tag("Date", text)
    }

    // ------------------------------------------------------------------ reading

    public enum ParseError: Error, Hashable, Sendable {
        case unusableStartingPosition(FENIssue?)
        /// A SAN token that is not a legal move in the position it was reached in.
        case illegalMove(String, afterPlies: Int)
    }

    public init(parsing text: String) throws {
        var scanner = Scanner(text)
        let tags = scanner.readTags()

        let startFEN = tags.first { $0.name == "FEN" }?.value ?? Self.standardStartFEN
        guard let game = Game(startFEN: startFEN) else {
            throw ParseError.unusableStartingPosition(Rules.validate(fen: startFEN).issue)
        }

        // One frame per open bracket. Moves always go to the innermost one, which is what
        // makes a Variation inside a Variation work without any special handling: it is the
        // same rule applied one level further in.
        var frames: [(game: Game, branchPoint: Int)] = [(game, -1)]

        // Evaluations arrive in comments *after* the move they belong to.
        for token in scanner.readMovetext() {
            let last = frames.count - 1
            switch token {
            case .move(let san):
                guard frames[last].game.apply(san: san) else {
                    throw ParseError.illegalMove(san, afterPlies: frames[last].game.plies.count)
                }
            case .evaluation(let score):
                frames[last].game.setEvaluation(
                    score, atPly: frames[last].game.plies.count - 1
                )
            case .variationStart:
                // A Variation is an alternative to the move just read, so it starts from the
                // position that move was played in.
                let branchPoint = frames[last].game.plies.count - 1
                guard branchPoint >= 0,
                      let rewound = frames[last].game.rewound(to: branchPoint)
                else {
                    // Brackets before any move have nothing to be an alternative to. Read
                    // them into a frame that gets thrown away rather than refusing the file.
                    frames.append((frames[last].game, -1))
                    continue
                }
                frames.append((rewound, branchPoint))
            case .variationEnd:
                guard frames.count > 1 else { continue }
                let frame = frames.removeLast()
                guard frame.branchPoint >= 0,
                      frame.game.plies.count > frame.branchPoint
                else { continue }
                frames[frames.count - 1].game.addVariation(
                    Array(frame.game.plies[frame.branchPoint...]), atPly: frame.branchPoint
                )
            }
        }

        self.tags = tags
        self.game = frames[0].game
    }
}

/// A hand-rolled scanner: PGN's movetext is a handful of token shapes, and pulling in a
/// parser generator to skip nested variations would cost more than it explains.
private struct Scanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) { characters = Array(text) }

    enum MovetextToken {
        case move(String)
        case evaluation(Score)
        case variationStart
        case variationEnd
    }

    mutating func readTags() -> [PGN.Tag] {
        var tags: [PGN.Tag] = []
        while true {
            skipWhitespace()
            guard peek() == "[" else { break }
            advance()
            let name = read(while: { !$0.isWhitespace && $0 != "\"" })
            skipWhitespace()
            guard peek() == "\"" else { skipPast("]"); continue }
            advance()
            var value = ""
            while let character = peek(), character != "\"" {
                if character == "\\", let next = peek(offset: 1), next == "\"" || next == "\\" {
                    advance()
                    value.append(next)
                } else {
                    value.append(character)
                }
                advance()
            }
            advance()  // closing quote
            skipPast("]")
            if !name.isEmpty { tags.append(PGN.Tag(name, value)) }
        }
        return tags
    }

    mutating func readMovetext() -> [MovetextToken] {
        var tokens: [MovetextToken] = []
        while let character = peek() {
            switch character {
            case _ where character.isWhitespace:
                advance()
            case "{":
                advance()
                let comment = read(while: { $0 != "}" })
                advance()
                if let score = Self.evaluation(in: comment) { tokens.append(.evaluation(score)) }
            case ";":
                _ = read(while: { !$0.isNewline })
            case "(":
                advance()
                tokens.append(.variationStart)
            case ")":
                advance()
                tokens.append(.variationEnd)
            case "$":
                advance()
                _ = read(while: { $0.isNumber })
            case _ where character.isNumber:
                // A move number, or a result token like "1-0" / "1/2-1/2".
                let word = read(while: { !$0.isWhitespace })
                if word.contains("-") || word.contains("/") { return tokens }
            case "*":
                return tokens
            default:
                let word = read(while: {
                    !$0.isWhitespace && $0 != "{" && $0 != "(" && $0 != ")"
                })
                if !word.isEmpty { tokens.append(.move(word)) }
            }
        }
        return tokens
    }

    private static func evaluation(in comment: String) -> Score? {
        guard let start = comment.range(of: "[%eval ") else { return nil }
        let rest = comment[start.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return nil }
        return Score(pgnText: String(rest[..<end]).trimmingCharacters(in: .whitespaces))
    }

    private func peek(offset: Int = 0) -> Character? {
        let wanted = index + offset
        return wanted < characters.count ? characters[wanted] : nil
    }

    private mutating func advance() { index += 1 }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace { advance() }
    }

    private mutating func skipPast(_ target: Character) {
        while let character = peek() {
            advance()
            if character == target { return }
        }
    }

    private mutating func read(while predicate: (Character) -> Bool) -> String {
        var text = ""
        while let character = peek(), predicate(character) {
            text.append(character)
            advance()
        }
        return text
    }
}
