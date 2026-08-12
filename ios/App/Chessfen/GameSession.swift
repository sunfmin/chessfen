import ChessfenKit
import Foundation

/// Where a game came from, which decides what can be done to it later.
enum GameOrigin: String, Hashable, Sendable, Codable {
    /// Set up by hand, from the standard position or an edited one.
    case fresh
    /// Read off a picture. Such a game can always be taken back to the Confirm Position
    /// gate, because the thing most likely to be wrong about it is a piece.
    case recognised

    /// Written into the PGN so the distinction survives a relaunch. Not a standard tag;
    /// PGN has no opinion about where a position came from, and readers ignore what they do
    /// not know.
    static let tagName = "Source"

    var tagValue: String { rawValue }
    var chinese: String { self == .recognised ? "识别" : "手摆" }
    var symbol: String { self == .recognised ? "camera" : "square.grid.3x3" }
}

/// One game being played, and everything the screen showing it needs.
///
/// The Game is the truth; this adds who is moving for each colour, which way up the board is,
/// where the player is looking, and the Analysis as it currently stands. It also owns the
/// engine loop, because "what should the engine be doing right now" has exactly one answer
/// and it follows from the Game, the cursor and the two Controllers.
@Observable final class GameSession: Identifiable, Hashable {
    let id = UUID()

    private(set) var game: Game
    var orientation: Orientation
    /// Which ply the player is looking at: 0 is the starting position, `plies.count` the
    /// latest. Browsing back does not change the Game — but playing from there does, and what
    /// used to follow becomes a Variation.
    private(set) var cursor: Int
    /// The Analysis of the position being looked at, replaced each time the engine reports a
    /// deeper one, and cleared the moment anything makes it stale.
    private(set) var analysis: Analysis?
    /// True while the engine is thinking about a move it is going to play itself, as opposed
    /// to advising.
    private(set) var isThinking = false
    private(set) var url: URL?
    let origin: GameOrigin
    /// The picture the position was read from, and the squares recognition was unsure of —
    /// kept so the gate can be returned to.
    var picture: RGBImage?
    var shaky: Set<Square>

    private var controllers: [PieceColour: Controller]
    private var tags: [PGN.Tag]
    private var searchTask: Task<Void, Never>?

    /// When the current player's turn began, and how long they took over the last one.
    /// Mirrored Time is the whole reason both are kept.
    private var turnBegan: ContinuousClock.Instant?
    private var lastHumanThink: Duration?

    private var engine: EngineService?
    private weak var library: GameLibrary?

    init(
        game: Game,
        // Both by hand unless asked otherwise. A board that starts moving on its own is a
        // surprise, and the engine is one switch away for anyone who wants an opponent.
        controllers: [PieceColour: Controller] = [.white: .hand, .black: .hand],
        orientation: Orientation = .whiteAtBottom,
        origin: GameOrigin = .fresh,
        picture: RGBImage? = nil,
        shaky: Set<Square> = [],
        url: URL? = nil,
        tags: [PGN.Tag] = []
    ) {
        self.game = game
        self.controllers = controllers
        self.orientation = orientation
        self.origin = origin
        self.picture = picture
        self.shaky = shaky
        self.url = url
        self.tags = tags
        self.cursor = game.plies.count
    }

    /// Reopens a saved game. The Controllers are not stored in PGN — nothing in the format has
    /// anywhere to put them — so a reopened game starts with both sides by hand, which is the
    /// reading that cannot surprise anyone by moving on its own.
    convenience init(entry: GameLibrary.Entry, library: GameLibrary? = nil) {
        let pgn = entry.pgn
        self.init(
            game: pgn?.game ?? Game(startFEN: PGN.standardStartFEN)!,
            controllers: [.white: .hand, .black: .hand],
            origin: entry.origin,
            picture: entry.origin == .recognised ? library?.picture(for: entry.url) : nil,
            url: entry.url,
            tags: pgn?.tags ?? []
        )
    }

    func attach(engine: EngineService?, library: GameLibrary?) {
        self.engine = engine
        self.library = library
    }

    func controller(for colour: PieceColour) -> Controller {
        controllers[colour] ?? .hand
    }

    func setController(_ controller: Controller, for colour: PieceColour) {
        guard controllers[colour] != controller else { return }
        controllers[colour] = controller
        // Changing who moves for the side already on the clock has to take effect now, not
        // next move — that is what the switch is for.
        retune()
    }

    // ---------------------------------------------------------------- browsing

    /// The Game as it stands where the player is looking.
    var viewed: Game { game.rewound(to: cursor) ?? game }

    var isAtLatest: Bool { cursor >= game.plies.count }

    /// The move that led to the position on screen.
    var lastMove: MoveSquares? {
        guard cursor > 0, game.plies.indices.contains(cursor - 1) else { return nil }
        return MoveSquares(uci: game.plies[cursor - 1].uci)
    }

    /// The lines that were played from the position on screen instead of the move that
    /// follows it.
    var variationsHere: [[Game.Ply]] { game.variations(atPly: cursor) }

    func step(by delta: Int) {
        let wanted = min(max(0, cursor + delta), game.plies.count)
        guard wanted != cursor else { return }
        cursor = wanted
        analysis = nil
        Feedback.shared.play(.move)
        retune()
    }

    func jumpToLatest() {
        guard cursor != game.plies.count else { return }
        cursor = game.plies.count
        analysis = nil
        retune()
    }

    /// Carries on down one of the lines that was left behind here.
    func enterVariation(_ index: Int) {
        guard game.promoteVariation(index, atPly: cursor) else { return }
        cursor += 1
        analysis = nil
        save()
        retune()
    }

    // ------------------------------------------------------------------ moves

    var isEngineTurn: Bool {
        isAtLatest && !game.isOver && controller(for: viewed.state.sideToMove) == .engine
    }

    /// Whether a person may move on the board as it is being looked at. True in the past as
    /// well as the present: playing from an earlier position is how a branch is made.
    var isHandTurn: Bool {
        guard !viewed.isOver else { return false }
        if !isAtLatest { return true }
        return controller(for: viewed.state.sideToMove) == .hand
    }

    /// A move made by a person. The clock this stops is what the engine will mirror.
    func play(_ move: Move) {
        guard isHandTurn else { return }
        if isAtLatest, let turnBegan { lastHumanThink = ContinuousClock.now - turnBegan }
        let branching = !isAtLatest && game.plies[cursor].uci != move.uci
        guard game.play(move, atPly: cursor) else {
            Feedback.shared.play(.refused)
            return
        }
        cursor += 1
        Feedback.shared.play(move, outcome: viewed.state.outcome)
        if branching { Feedback.shared.play(.check) }
        analysis = nil
        save()
        retune()
    }

    /// Takes the last move of the game off. Only from the latest position: in the middle of a
    /// game, going backwards is browsing, and deleting is not what a back button means.
    func undo() {
        guard isAtLatest, !game.plies.isEmpty else { return }
        searchTask?.cancel()
        game.undo()
        Feedback.shared.play(.move)
        // If undoing leaves the engine on the clock while the player is not, undo its move
        // too — otherwise it replies instantly and the player is exactly where they were.
        if controller(for: game.state.sideToMove) == .engine,
            controller(for: game.state.sideToMove.opposite) == .hand,
            !game.plies.isEmpty
        {
            game.undo()
        }
        cursor = game.plies.count
        analysis = nil
        lastHumanThink = nil
        save()
        retune()
    }

    // ------------------------------------------------------------- who starts

    /// Which colour moves first from the position this game began in.
    var startingSideToMove: PieceColour {
        game.startFEN.split(separator: " ").dropFirst().first == "b" ? .black : .white
    }

    /// Whether the game could begin with `colour` to move at all. Handing the move to the
    /// other side can make a position illegal, because their opponent may be standing in
    /// check — and a position nobody could have reached is not one to play from.
    func canStart(withSideToMove colour: PieceColour) -> Bool {
        restarted(withSideToMove: colour) != nil
    }

    /// Starts the game again from the position it began in, with `colour` to move.
    func restart(withSideToMove colour: PieceColour) {
        guard let fresh = restarted(withSideToMove: colour) else { return }
        searchTask?.cancel()
        // A game with moves in it has already been written to its own file. Leaving that file
        // behind and taking a new one means restarting never eats the record of what was
        // played — the old game is still in the library, exactly as it stood.
        if !game.plies.isEmpty { url = nil }
        game = fresh
        cursor = 0
        analysis = nil
        isThinking = false
        lastHumanThink = nil
        save()
        retune()
    }

    private func restarted(withSideToMove colour: PieceColour) -> Game? {
        guard var draft = PositionDraft(fen: game.startFEN) else { return nil }
        draft.sideToMove = colour
        return draft.game
    }

    // ----------------------------------------------------------------- engine

    /// Starts whatever the position calls for. Safe to call repeatedly.
    func retune() {
        searchTask?.cancel()
        searchTask = nil
        isThinking = false
        turnBegan = nil

        let position = viewed
        guard let engine, !position.isOver else { return }

        if isEngineTurn {
            isThinking = true
            let budget = MirroredTime.budget(mirroring: lastHumanThink)
            searchTask = Task { [weak self] in
                var last: Analysis?
                for await snapshot in engine.analyse(position, budget: budget) {
                    if Task.isCancelled { return }
                    self?.record(snapshot)
                    last = snapshot
                }
                guard let self, !Task.isCancelled else { return }
                isThinking = false
                if let uci = last?.bestMove, let move = position.state.move(matching: uci) {
                    playByEngine(move)
                }
            }
        } else {
            turnBegan = ContinuousClock.now
            searchTask = Task { [weak self] in
                // Unbounded: it deepens for as long as the player is thinking, and what it
                // recommends keeps changing (docs/adr/0009).
                for await snapshot in engine.analyse(position, budget: .untilStopped) {
                    if Task.isCancelled { return }
                    self?.record(snapshot)
                }
            }
        }
    }

    /// Cuts the engine's thinking short and takes whatever it likes best right now.
    ///
    /// Stopping a search is not abandoning it: Stockfish still reports its best move, so this
    /// plays the move the engine would have played, just sooner.
    func moveNow() {
        guard isThinking else { return }
        engine?.stop()
    }

    /// A move the engine played for itself. It does not touch the mirror — the engine's own
    /// thinking time is not a thinking time for the engine to mirror.
    private func playByEngine(_ move: Move) {
        guard isAtLatest, game.apply(move) else { return }
        cursor = game.plies.count
        Feedback.shared.play(move, outcome: game.state.outcome)
        analysis = nil
        save()
        retune()
    }

    /// Stops thinking — the screen has gone away, or the app has.
    func suspend() {
        searchTask?.cancel()
        searchTask = nil
        isThinking = false
        engine?.stop()
    }

    private func record(_ snapshot: Analysis) {
        analysis = snapshot
        // Real-time recording: the ply just played gets the Score of the position it led to,
        // refined as the search deepens. A Review recomputes all of them at one Depth later
        // and overwrites these (docs/adr/0009).
        if let score = snapshot.best?.score, cursor > 0 {
            game.setEvaluation(score, atPly: cursor - 1)
        }
    }

    // --------------------------------------------------------------- storage

    var pgn: PGN {
        var roster = tags
        func set(_ name: String, _ value: String) {
            if let index = roster.firstIndex(where: { $0.name == name }) {
                roster[index].value = value
            } else {
                roster.append(PGN.Tag(name, value))
            }
        }
        set("Event", "Chessfen")
        set("White", controller(for: .white).playerName)
        set("Black", controller(for: .black).playerName)
        set("Result", game.resultToken)
        set(GameOrigin.tagName, origin.tagValue)
        if roster.first(where: { $0.name == "Date" }) == nil {
            roster.append(PGN.dateTag())
        }
        return PGN(game: game, tags: roster)
    }

    /// Writes after every move. A game is a few kilobytes of text, so there is no reason for
    /// an app that can be killed at any moment to hold one in memory only.
    ///
    /// A game nobody has moved in yet is not written at all. Recognising a board, looking at
    /// what the engine makes of it and going back is a thing people do constantly, and it
    /// should not leave a trail of empty games behind it. The first move is what makes a game
    /// worth keeping — and once a file exists it keeps being written to, even if the moves are
    /// taken back off it again.
    func save() {
        guard let library else { return }
        guard url != nil || !game.plies.isEmpty else { return }
        let isNew = url == nil
        if url == nil { url = library.newURL() }
        guard let url else { return }
        library.write(pgn, to: url)
        // The picture goes beside the game the first time it is written, so that a recognised
        // game can still be checked against its photograph after a relaunch.
        if isNew, origin == .recognised, let picture {
            library.writePicture(picture, for: url)
        }
    }

    /// Replaces the recorded Scores with a Review's, which are comparable with each other.
    func applyReview(_ scores: [Score?]) {
        for (ply, score) in scores.enumerated() where score != nil {
            game.setEvaluation(score, atPly: ply)
        }
        save()
    }

    static func == (left: GameSession, right: GameSession) -> Bool { left === right }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
