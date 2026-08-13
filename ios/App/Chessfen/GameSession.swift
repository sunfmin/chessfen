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

    /// How the running search is getting on — how long it has been at it and how deep it has got.
    ///
    /// Apart from the Analysis on purpose, because it is not advice: a Depth and a stopwatch are a
    /// report of what the phone is doing, so practice, which refuses to show what the engine
    /// *thinks*, has no reason to hide them. It is what a thumb held on 让引擎走 is told.
    private(set) var searchProgress: SearchProgress?

    struct SearchProgress: Hashable, Sendable {
        var depth: Int
        var selectiveDepth: Int
        var milliseconds: UInt64

        var seconds: Double { Double(milliseconds) / 1000 }
    }
    private(set) var url: URL?
    let origin: GameOrigin
    /// The picture the position was read from, and the squares recognition was unsure of —
    /// kept so the gate can be returned to.
    var picture: RGBImage?
    var shaky: Set<Square>

    /// Whether the engine keeps its opinion to itself. This is the practice switch: no advisory
    /// search runs, no Score is drawn, and nothing the engine thinks is written into the plies —
    /// so a game played this way carries no marks, and 复盘 is where it finally meets the engine
    /// at one uniform Depth (docs/adr/0009). Playing a whole game with the engine looking over
    /// your shoulder and playing one out yourself are different exercises, and only the second
    /// one tells you what you would have done.
    ///
    /// It does not silence the engine as an *opponent*: a bounded search for the engine's own
    /// move is not advice, and playing a side without being told what it thinks of your last
    /// move is exactly the exercise.
    ///
    /// Not stored. PGN has nowhere to put it, and like the Controllers it is a way of playing
    /// rather than something about the game, so a reopened game starts with the engine talking.
    private(set) var isPractising = false

    private var controllers: [PieceColour: Controller]
    /// The clock somebody has put the engine on, if anybody has. Nil means the game decides —
    /// see `thinkingTime`, which is the one to read.
    ///
    /// Not stored, like the Controllers it goes with: PGN has nowhere to put it, and it is a way
    /// of playing rather than something about the game.
    private var chosenThinkingTime: ThinkingTime?
    private var tags: [PGN.Tag]
    private var searchTask: Task<Void, Never>?

    /// When the current player's turn began, and how long they took over the last one.
    /// Mirrored Time is the whole reason both are kept.
    private var turnBegan: ContinuousClock.Instant?
    private var lastHumanThink: Duration?
    /// The best move known to the search the engine was asked for — the arrow it started from, then
    /// whatever it has found since. What letting go of the button plays.
    private var askedBest: String?
    /// Whether the button has already been let go of while its search was still starting up.
    private var isAskReleased = false

    private var engine: (any Engine)?
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
        tags: [PGN.Tag] = [],
        /// Which ply to open on. The latest by default, which is where a game being played is.
        viewing: Int? = nil
    ) {
        self.game = game
        self.controllers = controllers
        self.orientation = orientation
        self.origin = origin
        self.picture = picture
        self.shaky = shaky
        self.url = url
        self.tags = tags
        self.cursor = min(max(0, viewing ?? game.plies.count), game.plies.count)
    }

    /// Reopens a saved game, at the position it began in.
    ///
    /// The beginning rather than the end, because opening a game that is over is reading it: the
    /// moves are there to be walked through, and the last position is the one thing about a
    /// finished game you already know. 下一步 is the first tap either way.
    ///
    /// The Controllers are not stored in PGN — nothing in the format has anywhere to put them — so
    /// a reopened game starts with both sides by hand, which is the reading that cannot surprise
    /// anyone by moving on its own.
    convenience init(entry: GameLibrary.Entry, library: GameLibrary? = nil) {
        let pgn = entry.pgn
        self.init(
            game: pgn?.game ?? Game(startFEN: PGN.standardStartFEN)!,
            controllers: [.white: .hand, .black: .hand],
            origin: entry.origin,
            picture: entry.origin == .recognised ? library?.picture(for: entry.url) : nil,
            url: entry.url,
            tags: pgn?.tags ?? [],
            viewing: 0
        )
    }

    /// A saved game, opened ready to play: the engine attached and the library it saves back to.
    /// Defined once because more than one screen opens games now — the library and a collection.
    static func opened(
        _ entry: GameLibrary.Entry, engine: EngineHost, library: GameLibrary
    ) -> GameSession {
        let session = GameSession(entry: entry, library: library)
        session.attach(engine: engine.service, library: library)
        return session
    }

    func attach(engine: (any Engine)?, library: GameLibrary?) {
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

    /// Whether the engine is holding either Controller, which is when its clock is worth showing.
    var isEnginePlaying: Bool {
        controller(for: .white) == .engine || controller(for: .black) == .engine
    }

    /// Both Controllers on the engine: the app playing itself, with nobody on the clock.
    var isSelfPlaying: Bool {
        controller(for: .white) == .engine && controller(for: .black) == .engine
    }

    /// How long the engine gets over a move it plays for a colour it controls.
    ///
    /// What somebody chose, or what the game calls for if nobody has: Mirrored Time against a
    /// person, three seconds a move when the engine is playing itself.
    ///
    /// Self-play also overrules a standing choice of Mirrored Time, which is the one setting the
    /// game is allowed to refuse. It is not a preference there so much as a question with no
    /// answer — there is no player's last move to mirror — and a clock that quietly meant one
    /// second for ever is worse than the app saying which clock it is actually using.
    var thinkingTime: ThinkingTime {
        guard let chosenThinkingTime else { return isSelfPlaying ? .selfPlay : .mirrored }
        if chosenThinkingTime == .mirrored, isSelfPlaying { return .selfPlay }
        return chosenThinkingTime
    }

    /// Puts the engine on a different clock, mid-move if that is when it is said.
    ///
    /// Now rather than next move, for the same reason changing a Controller is: a search that
    /// carried on under the old clock would make the control a promise about the move after this
    /// one, and the move being waited for is the one anybody reaches for this because of. The
    /// running search starts again on the new clock rather than being trimmed to it — the time
    /// asked for is the time it gets.
    func setThinkingTime(_ time: ThinkingTime) {
        guard thinkingTime != time else { return }
        chosenThinkingTime = time
        retune()
    }

    /// Turns the engine's advice off, or back on. Also takes effect now: a number left standing
    /// from the search that has just been called off is the one thing practice must not show.
    func setPractising(_ practising: Bool) {
        guard isPractising != practising else { return }
        isPractising = practising
        analysis = nil
        retune()
    }

    /// The collection this game is filed under, according to its own file.
    ///
    /// Read from the tags rather than carried alongside them, so that it cannot disagree with what
    /// the library shows — and so a game that has never been saved has no collection, which is the
    /// truth about it.
    var collection: String? {
        guard let event = tags.first(where: { $0.name == "Event" })?.value,
            !GameLibrary.unfiledEvents.contains(event)
        else { return nil }
        return event
    }

    // ------------------------------------------------------------- the reading

    /// Whether somebody has filed this game into a collection, which is them saying they are keeping
    /// it — and so also saying the position it starts from is the one they meant.
    var isFiled: Bool { collection != nil }

    /// Whether this game's starting position can be taken back to the editor. True for anything
    /// read off a picture, for as long as the game exists: the thing most likely to be wrong
    /// about such a game is a piece, and finding that out ten moves later is the normal case.
    ///
    /// Except once it has been filed. A game somebody has put in a collection has been looked at
    /// and kept, so either the reading was right or it has already been put right, and a screen
    /// that goes on asking about the pieces is asking a question that was answered.
    var canEditPosition: Bool { origin == .recognised && !isFiled }

    /// The squares recognition was unsure about, while they are still worth pointing at. Once a
    /// move has been played the position has been accepted in practice, and rings on the board
    /// would be nothing but noise — as they would on a game that has been filed, for the same
    /// reason `canEditPosition` stops offering the editor.
    var unconfirmedSquares: Set<Square> {
        canEditPosition && game.plies.isEmpty ? shaky : []
    }

    /// Swaps the position the game starts from. Only for a game nobody has moved in yet — which
    /// is the case this exists for: correcting a piece straight after the photograph should fix
    /// the game in front of you, not leave a second record behind.
    func replaceStart(with fresh: Game) -> Bool {
        guard game.plies.isEmpty else { return false }
        searchTask?.cancel()
        game = fresh
        cursor = 0
        analysis = nil
        isThinking = false
        lastHumanThink = nil
        shaky = []
        retune()
        return true
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

    /// Back to the position the game began in, in one tap.
    ///
    /// Browsing, not undoing: the game is untouched and every move is still there to be walked
    /// through again. It is the other end of `jumpToLatest`, and between them a game is readable
    /// without a single move being taken off it.
    func jumpToStart() {
        guard cursor != 0 else { return }
        cursor = 0
        analysis = nil
        Feedback.shared.play(.move)
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

    // -------------------------------------------------------- one move, asked for

    /// Whether the engine can be asked to take this move, for either colour.
    ///
    /// A search already running does not make it false. The button that asks is held down while the
    /// search it started runs, and a control that disabled itself under the finger would never hear
    /// it let go.
    ///
    /// The engine's own turn does, though: it is already walking this move under its own Controller,
    /// and 马上走 is how you stop waiting for it. Asking a second time for a move that is already
    /// being played is two controls doing one job.
    var canPlayBestMove: Bool { engine != nil && !viewed.isOver && !isEngineTurn }

    /// Starts the engine thinking about a move it will play when it is let go.
    ///
    /// Held time *is* thinking time, which is the same bargain the engine's own moves are played
    /// under (Mirrored Time, docs/adr/0009): it is never handicapped, so the only thing that shapes
    /// how well it plays is how long it is left alone — and here that is a thumb on a button. A tap
    /// is a snap answer, two seconds is a considered one, and neither is the app deciding.
    ///
    /// Not a Controller and not advice left standing: one move, asked for by hand, for whichever
    /// colour is on the clock.
    func beginAskedMove() {
        // Once per press. A press arrives as a drag of no distance, which reports as it is held, and
        // the button cannot know it is already down until the state saying so has come back around
        // to it — so two of them can reach here before it does. Nothing else is thinking on a hand
        // turn, which is what makes this the honest guard.
        guard canPlayBestMove, !isThinking, let engine else { return }
        // What the arrow on the board is pointing at. It is the answer already, for the case where
        // the press turns out to be a tap and the search has not said anything of its own yet.
        askedBest = analysis?.bestMove
        isAskReleased = false
        let position = viewed
        searchTask?.cancel()
        searchProgress = nil
        isThinking = true
        searchTask = Task { [weak self] in
            // Unbounded: how long it runs is how long the button is held.
            for await snapshot in engine.analyse(position, budget: .untilStopped) {
                if Task.isCancelled { return }
                guard let self else { return }
                record(snapshot)
                if let best = snapshot.bestMove { askedBest = best }
                // The thumb came up before the engine had said anything worth playing, so this
                // first word is the answer.
                if isAskReleased { break }
            }
            guard let self, !Task.isCancelled else { return }
            finishAskedMove(in: position)
        }
    }

    /// Let go: the engine stops where it has got to and plays what it likes best.
    ///
    /// The move is played here rather than left to the stream ending, because a press can be shorter
    /// than the trip to the engine and back: asking a search that has not started yet to stop is a
    /// no-op, and a game that only moves when the engine happens to notice is not a button. So a
    /// release plays what is known at that instant and takes the search down with it — and the one
    /// case where nothing is known yet waits for the first snapshot, which is the soonest an answer
    /// can exist at all.
    func endAskedMove() {
        guard isThinking else { return }
        isAskReleased = true
        guard askedBest != nil else {
            engine?.stop()
            return
        }
        let position = viewed
        searchTask?.cancel()
        searchTask = nil
        finishAskedMove(in: position)
    }

    private func finishAskedMove(in position: Game) {
        isThinking = false
        isAskReleased = false
        let uci = askedBest
        askedBest = nil
        guard let uci, let move = position.state.move(matching: uci) else { return }
        playAsked(move)
    }

    /// A move the engine was asked for. Like a hand move in every way except the clock: the time
    /// the engine mirrors is a record of how long the *player* took, and this was not that.
    private func playAsked(_ move: Move) {
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
        // Nothing starts while the engine is paused — not the standing Analysis, and not the
        // engine's own move, which takes a bounded budget and so would otherwise slip past the
        // gate in `analyse`. `retune` is called from more places than the app coming back
        // (`onAppear`, the engine having just played), so the answer to "what should the engine
        // be doing right now" has to include "nothing, nobody is watching".
        guard let engine, !position.isOver, !engine.isPaused else { return }

        if isEngineTurn {
            isThinking = true
            // Mirrored Time is only the default, and only against a person: with both Controllers
            // on the engine there is no last human move to mirror, and there is a named clock
            // instead (`thinkingTime`).
            let budget = thinkingTime.budget(mirroring: lastHumanThink)
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
            // Before the practice gate: the clock the engine mirrors is a record of how long the
            // player took, and that is true whether or not anyone was being advised.
            turnBegan = ContinuousClock.now
            // Practice turns off exactly this search — the one whose only product is advice. It
            // is refused here rather than in the screen for the reason the pause is: "what should
            // the engine be doing right now" has one answer, and a screen that forgot would leave
            // a phone deepening a search nobody is allowed to see the result of.
            guard !isPractising else { return }
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
        searchProgress = SearchProgress(
            depth: snapshot.depth,
            selectiveDepth: snapshot.selectiveDepth,
            milliseconds: snapshot.timeMilliseconds
        )
        // While practising, the only search still running is the engine thinking about its own
        // move — and what that search thinks of the position is advice, whichever question it was
        // asked. It is dropped rather than merely hidden, so the game's plies stay unmarked and
        // the Review has nothing to disagree with.
        guard !isPractising else { return }
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
        var written = PGN(game: game, tags: tags)
        // Event is only filled in when the game is not in a collection. It used to be set to the
        // app's name unconditionally, which would have rubbed out the collection of every filed game
        // on its next move — the tag naming the collection and the tag naming the app are the same
        // tag, and the file is the only place either of them lives (docs/adr/0010).
        if written.tag("Event").map(GameLibrary.unfiledEvents.contains) ?? true {
            written.setTag("Event", to: "Chessfen")
        }
        written.setTag("White", to: controller(for: .white).playerName)
        written.setTag("Black", to: controller(for: .black).playerName)
        written.setTag("Result", to: game.resultToken)
        written.setTag(GameOrigin.tagName, to: origin.tagValue)
        if written.tag("Date") == nil {
            written.tags.append(PGN.dateTag())
        }
        return written
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
