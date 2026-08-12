import ChessfenKit
// For `onReceive` only: the sound setting travels through iCloud, and a notification is how a
// device hears that another one has changed it.
import Combine
import SwiftUI

/// The board, what the engine makes of it, and the few things you do to it.
///
/// No scrolling: the board is the hero and it has to sit still under a navigation bar, not slide
/// beneath it. Everything else is a strip of fixed height below it, and the board takes whatever
/// is left over — which on a small phone means a slightly smaller board rather than a screen
/// that has to be dragged.
struct GameScreen: View {
    let session: GameSession
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var selected: Square?
    @State private var promotion: PromotionRequest?
    @State private var isSoundOn = Feedback.shared.isSoundOn

    struct PromotionRequest: Identifiable {
        let id = UUID()
        let moves: [Move]
    }

    var body: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size)
            VStack(spacing: 0) {
                header
                board.frame(width: side, height: side)
                // No bar while practising. Empty, it sits exactly half white and reads as a
                // considered 0.00 — the most misleading thing this screen could show someone who
                // has asked not to be told.
                if !session.isPractising {
                    EvalBar(score: session.analysis?.best?.score, orientation: session.orientation)
                        .frame(width: side)
                        .padding(.top, 7)
                }
                // Everything below the board scrolls if it has to. The board itself is outside
                // this, which is what keeps it from sliding under the navigation bar and from
                // changing size when what is underneath it grows.
                ScrollView {
                    VStack(spacing: 0) {
                        series
                        corrections
                        engineLines
                        notation
                        controls
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Palette.parchment)
        .navigationTitle("对局")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        path.append(.review(session))
                    } label: {
                        Label("复盘", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    Button {
                        path.append(.confirm(PositionProposal(reopening: session)))
                    } label: {
                        Label("改棋子", systemImage: "hand.point.up.left")
                    }
                    Toggle(isOn: $isSoundOn) {
                        Label("音效", systemImage: isSoundOn ? "speaker.wave.2" : "speaker.slash")
                    }
                    if let url = session.url {
                        ShareLink(item: url) {
                            Label("导出 PGN", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Re-attached on every appearance: the engine may have finished starting while the
            // library was on screen, and coming back from a Review means the search this screen
            // wants is not the one that just ran.
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        .onDisappear { session.suspend() }
        .onChange(of: isSoundOn) { _, isOn in Feedback.shared.isSoundOn = isOn }
        // The setting travels between devices (docs/adr/0012), so it can change while this
        // screen is the one on show — and a toggle that disagrees with the sound is worse than
        // no toggle.
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            isSoundOn = Feedback.shared.isSoundOn
        }
        .onChange(of: engine.isReady) { _, ready in
            guard ready else { return }
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        // The Analysis this screen wants is unbounded, and the engine will not start one while
        // the app is away — so leaving is a suspend and coming back is a fresh `retune`, not a
        // search that was left running underneath. `EngineHost.isActive` rather than the scene
        // phase, so there is one answer to when that is.
        .onChange(of: engine.isActive) { _, active in
            if active {
                session.retune()
            } else {
                session.suspend()
            }
        }
        .confirmationDialog(
            "升变成什么？", isPresented: .constant(promotion != nil), titleVisibility: .visible
        ) {
            ForEach(promotion?.moves ?? [], id: \.uci) { move in
                Button(move.promotion?.chinese ?? move.uci) {
                    session.play(move)
                    promotion = nil
                }
            }
            Button("取消", role: .cancel) { promotion = nil }
        }
    }

    // ------------------------------------------------------------------ parts

    /// Who is on the clock, and what the engine currently thinks of it.
    ///
    /// Two lines: the state of the game and the number share a baseline, so the eye reads them
    /// as one sentence; everything about how the number was arrived at sits under it.
    private var header: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewed.chineseTurn).eyebrow()
                if viewed.state.inCheck, !viewed.isOver {
                    Text("被将")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.alarm)
                }
                Spacer(minLength: 8)
                if session.isPractising {
                    // Where the number lives, so its absence is accounted for rather than just an
                    // empty corner someone reads as a broken engine.
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash").font(.caption)
                        Text("练习").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Palette.inkSoft)
                } else {
                    Text(headlineScore?.displayText ?? "—")
                        .font(.clock(32))
                        .foregroundStyle(headlineScore == nil ? Palette.inkSoft : Palette.analysis)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 8) {
                if session.isThinking {
                    // Mirrored Time means the engine takes about as long as the player just did,
                    // which is right most of the time and longer than anyone wants to sit through
                    // the rest of it. Stopping the search does not change which move it picks; it
                    // just stops waiting.
                    Button { session.moveNow() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "forward.fill").font(.caption2)
                            Text("马上走").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Palette.analysis, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if !session.isAtLatest {
                    Button {
                        selected = nil
                        session.jumpToLatest()
                    } label: {
                        Text("在看第 \(session.cursor)/\(session.game.plies.count) 步 · 回到最新")
                            .font(.caption)
                            .foregroundStyle(Palette.analysis)
                    }
                    .buttonStyle(.plain)
                } else if case .unavailable = engine.status {
                    Text("没有引擎").font(.caption).foregroundStyle(Palette.alarm)
                }
                Spacer(minLength: 4)
                SearchMeter(analysis: session.analysis)
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    /// What the number at the top says. The engine's view of the position on screen, or nothing
    /// at all until it has one — never a stale number from the previous position.
    private var headlineScore: Score? { session.analysis?.best?.score }

    /// How big the board is, and it depends on the screen and nothing else.
    ///
    /// It used to take whatever height was left over, which meant the board changed size when the
    /// engine found a third line to show — the one thing on this screen that must never move. So
    /// it is sized from the width, all but full bleed, and only shrinks on a screen too short to
    /// leave anything for the panel underneath. Rounded to a multiple of eight so every square is
    /// a whole number of points and no grid line lands on a half pixel.
    static func boardSide(in size: CGSize) -> CGFloat {
        let byWidth = size.width - 16
        let byHeight = max(240, size.height - 300)
        return (min(byWidth, byHeight) / 8).rounded(.down) * 8
    }

    private var board: some View {
        BoardView(
            pieces: pieces,
            orientation: session.orientation,
            lastMove: session.lastMove,
            checks: checkSquares,
            // The doubtful squares stay ringed on the board being played on, right up until the
            // first move — which is what replaces the old gate: the reading's own uncertainty is
            // visible where it matters, and 改棋子 is one tap away (docs/adr/0011).
            suspects: session.unconfirmedSquares,
            selected: selected,
            destinations: Set(candidateMoves.map(\.to)),
            captures: Set(candidateMoves.filter(\.isCapture).map(\.to)),
            recommendation: recommendation,
            isInteractive: session.isHandTurn,
            onTap: tap
        )
    }

    /// Where this game sits in its collection, and the way to the next one.
    ///
    /// Working through a set is the reason collections exist, and going back to the library between
    /// every position is the thing that makes anyone stop. The order is the library's own — by name
    /// — read fresh each time rather than captured when the game opened, so renaming a game during a
    /// session moves it where you just said it goes.
    @ViewBuilder private var series: some View {
        if let collection = session.collection, let place = placeInSeries {
            HStack(spacing: 10) {
                seriesButton("上一局", symbol: "chevron.left", at: place.index - 1)
                VStack(spacing: 1) {
                    Text(collection)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("第 \(place.index + 1)/\(place.entries.count) 局")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
                seriesButton("下一局", symbol: "chevron.right", at: place.index + 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private func seriesButton(_ label: String, symbol: String, at index: Int) -> some View {
        let target = placeInSeries?.entries[safe: index]
        return Button {
            if let target { drill(to: target) }
        } label: {
            HStack(spacing: 3) {
                if symbol == "chevron.left" { Image(systemName: symbol).font(.caption2) }
                Text(label).font(.caption.weight(.semibold))
                if symbol == "chevron.right" { Image(systemName: symbol).font(.caption2) }
            }
            .foregroundStyle(target == nil ? Palette.inkSoft : Palette.analysis)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
    }

    /// The games in this one's collection, and which one this is. Nil for a game that is not in a
    /// collection, or one not yet written to disk — there is nothing to be next to.
    private var placeInSeries: (entries: [GameLibrary.Entry], index: Int)? {
        guard let collection = session.collection, let url = session.url,
            let entries = library.collections.first(where: { $0.name == collection })?.entries,
            let index = entries.firstIndex(where: { $0.url == url })
        else { return nil }
        return (entries, index)
    }

    /// The way back to the editor, shown as a job to do rather than hidden in a menu — a piece
    /// read wrong is the one thing about a photographed game that has to be easy to fix.
    @ViewBuilder private var corrections: some View {
        if session.canEditPosition {
            Button {
                path.append(.confirm(PositionProposal(reopening: session)))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.shaky.isEmpty ? "hand.point.up.left" : "questionmark.circle")
                    Text(correctionText)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("改棋子").font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(session.shaky.isEmpty ? Palette.ink : Palette.alarm)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    (session.shaky.isEmpty ? Palette.chipRest : Palette.alarm.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var correctionText: String {
        let count = session.shaky.count
        return count == 0 ? "照片认错了棋子？" : "橙框那 \(count) 个格子拿不太准"
    }

    /// What the engine is looking at, three lines deep. A fixed height, because the lines change
    /// several times a second as the search deepens and a moving layout would be unreadable.
    private var engineLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            // First, and ahead of the game being over: someone practising has asked for this space
            // to be quiet, and what belongs in it instead is where the comparison happens.
            if session.isPractising {
                Text(
                    viewed.isOver
                        ? "这局走完了。去「复盘」，引擎会把每一步重新打一遍分。"
                        : "练习中，引擎不给意见。走完用「复盘」跟它对一遍。"
                )
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
            } else if let analysis = session.analysis, !analysis.lines.isEmpty {
                ForEach(Array(analysis.lines.prefix(3).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        ScoreCell(score: line.score, prominent: index == 0)
                            .frame(width: 56, alignment: .leading)
                        Text(line.san.prefix(8).joined(separator: " "))
                            .font(.notation)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(index == 0 ? Palette.ink : Palette.inkSoft)
                    }
                }
            } else if viewed.isOver {
                Text(viewed.resultToken == "*" ? "对局结束" : "终局 \(viewed.resultToken)")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            } else if case .unavailable(let reason) = engine.status {
                Text(reason).font(.footnote).foregroundStyle(Palette.alarm)
            } else {
                Text("引擎在算").font(.footnote).foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // The recommendation keeps changing as the search deepens, and that is the point
        // (docs/adr/0009) — so it must not make the layout jump while it does.
        .animation(.none, value: session.analysis?.depth)
    }

    /// The moves, set on the page rather than in a card: it is a record, not a control.
    private var notation: some View {
        ScrollView {
            Text(notationText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5).padding(.horizontal, 16)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TransportButton(label: "上一步", symbol: "chevron.left") {
                    selected = nil
                    session.step(by: -1)
                }
                .disabled(session.cursor == 0)
                .opacity(session.cursor == 0 ? 0.4 : 1)

                TransportButton(label: "下一步", symbol: "chevron.right", trailingSymbol: true) {
                    selected = nil
                    session.step(by: 1)
                }
                .disabled(session.isAtLatest)
                .opacity(session.isAtLatest ? 0.4 : 1)

                TransportButton(label: "悔棋", symbol: "arrow.uturn.backward") {
                    selected = nil
                    session.undo()
                }
                .disabled(!session.isAtLatest || session.game.plies.isEmpty)
                .opacity(!session.isAtLatest || session.game.plies.isEmpty ? 0.4 : 1)
            }

            if !session.variationsHere.isEmpty { variations }

            // Two clusters to a line, twice. Four separate rows of one control each was mostly
            // empty space, and pairing them is also truer: which way up the board is pairs with
            // who started, and white's player only means anything next to black's.
            HStack(spacing: 10) {
                ChipCluster(
                    title: "视角",
                    options: [
                        .init(value: Orientation.whiteAtBottom, label: "白在下"),
                        .init(value: Orientation.blackAtBottom, label: "黑在下"),
                    ],
                    selection: session.orientation
                ) { orientation in
                    withAnimation(.snappy(duration: 0.2)) { session.orientation = orientation }
                }
                Spacer(minLength: 2)
                ChipCluster(
                    title: "先走",
                    options: [
                        .init(
                            value: PieceColour.white, label: "白先走",
                            isEnabled: session.canStart(withSideToMove: .white)
                        ),
                        .init(
                            value: PieceColour.black, label: "黑先走",
                            isEnabled: session.canStart(withSideToMove: .black)
                        ),
                    ],
                    selection: session.startingSideToMove
                ) { colour in
                    selected = nil
                    session.restart(withSideToMove: colour)
                }
            }

            HStack(spacing: 10) {
                ForEach([PieceColour.white, .black], id: \.self) { colour in
                    ChipCluster(
                        title: colour == .white ? "白方" : "黑方",
                        options: Controller.allCases.map {
                            .init(
                                value: $0, label: $0.chinese,
                                isEnabled: $0 == .hand || engine.isReady
                            )
                        },
                        selection: session.controller(for: colour)
                    ) { controller in
                        session.setController(controller, for: colour)
                    }
                    if colour == .white { Spacer(minLength: 2) }
                }
            }

            // Under the two Controllers, because it is the third thing the engine can be asked to
            // do here and it only means anything next to them: those two say whether it moves,
            // this one says whether it talks. It was in the menu, which is the wrong place for the
            // same reason the others are not there — it is a fact about the game in front of you.
            HStack(spacing: 10) {
                ChipCluster(
                    title: "意见",
                    options: [
                        .init(value: false, label: "看引擎", isEnabled: engine.isReady),
                        .init(value: true, label: "自己练"),
                    ],
                    selection: session.isPractising
                ) { practising in
                    session.setPractising(practising)
                }
                Spacer(minLength: 2)
            }

            if !session.game.plies.isEmpty {
                Text("换先走方会重开一局，走过的这局留在记录里")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// The lines that were played from here instead of the move that follows.
    private var variations: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(session.variationsHere.enumerated()), id: \.offset) { index, line in
                Button {
                    selected = nil
                    session.enterVariation(index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch").font(.caption2)
                        Text(line.prefix(6).map(\.san).joined(separator: " "))
                            .font(.notation)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.analysis)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.analysis.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ------------------------------------------------------------------ doing

    /// Opens the next game in the collection in place of this one.
    ///
    /// It replaces the top of the path rather than pushing, so working through fifty positions does
    /// not build a stack of fifty screens to come back through — and the way back is still the
    /// library, which is where it was.
    ///
    /// How you are working carries over: which way up the board is, whether the engine is advising,
    /// and who is playing each side. Those are settings for the session you are having, not facts
    /// about the game, and having to set them again for every position is exactly the friction that
    /// makes a set of fifty not get done.
    private func drill(to entry: GameLibrary.Entry) {
        session.suspend()
        let next = GameSession(entry: entry, library: library)
        next.attach(engine: engine.service, library: library)
        next.orientation = session.orientation
        next.setPractising(session.isPractising)
        for colour in [PieceColour.white, .black] {
            next.setController(session.controller(for: colour), for: colour)
        }
        selected = nil
        path[path.count - 1] = .game(next)
    }

    private func tap(_ square: Square) {
        guard session.isHandTurn else { return }

        if let selected {
            let moves = viewed.state.moves(from: selected).filter { $0.to == square }
            // More than one move to the same square means a promotion, and only a promotion.
            if moves.count > 1 {
                promotion = PromotionRequest(moves: moves)
                self.selected = nil
                return
            }
            if let move = moves.first {
                session.play(move)
                self.selected = nil
                return
            }
        }

        // Not a destination, so it is either a new selection or a deselection.
        if let piece = pieces[square], piece.colour == viewed.state.sideToMove {
            selected = square
        } else {
            if selected != nil { Feedback.shared.play(.refused) }
            selected = nil
        }
    }

    /// The game where the player is looking, which is what everything on this screen is about.
    private var viewed: Game { session.viewed }

    private var pieces: [Square: Piece] {
        BoardRenderer.placement(viewed.state.fen) ?? [:]
    }

    private var candidateMoves: [Move] {
        guard let selected, session.isHandTurn else { return [] }
        return viewed.state.moves(from: selected)
    }

    private var checkSquares: Set<Square> {
        guard viewed.state.inCheck else { return [] }
        var squares = Set(viewed.state.checkers)
        // The king in check is the square a player looks for, and it is not in `checkers`.
        for (square, piece) in pieces
        where piece.kind == .king && piece.colour == viewed.state.sideToMove {
            squares.insert(square)
        }
        return squares
    }

    private var recommendation: MoveSquares? {
        session.analysis?.bestMove.flatMap { MoveSquares(uci: $0) }
    }

    private var notationText: AttributedString {
        var text = AttributedString()
        var number = Int(session.game.startFEN.split(separator: " ").last.flatMap { Int($0) } ?? 1)
        var sideToMove: PieceColour =
            session.game.startFEN.split(separator: " ").dropFirst().first == "b" ? .black : .white

        for (index, ply) in session.game.plies.enumerated() {
            if sideToMove == .white {
                text += styled("\(number). ", Palette.inkSoft)
            } else if text.characters.isEmpty {
                text += styled("\(number)... ", Palette.inkSoft)
            }
            // The move that led to the position on screen, so browsing has somewhere to point.
            let isCursor = index == session.cursor - 1
            var san = styled(ply.san, isCursor ? Palette.analysis : Palette.ink)
            if isCursor { san.font = .notation.weight(.bold) }
            text += san
            if !ply.variations.isEmpty {
                text += styled("⁽\(ply.variations.count)⁾", Palette.inkSoft)
            }
            text += styled(" ", Palette.ink)
            if sideToMove == .black { number += 1 }
            sideToMove = sideToMove.opposite
        }
        return text.characters.isEmpty ? styled("从这里开始走", Palette.inkSoft) : text
    }

    private func styled(_ string: String, _ colour: Color) -> AttributedString {
        var piece = AttributedString(string)
        piece.font = .notation
        piece.foregroundColor = colour
        return piece
    }
}
