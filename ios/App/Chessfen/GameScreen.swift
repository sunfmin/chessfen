import ChessfenKit
import SwiftUI

struct GameScreen: View {
    let session: GameSession
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    @State private var selected: Square?
    @State private var promotion: PromotionRequest?
    @State private var isSoundOn = Feedback.shared.isSoundOn

    struct PromotionRequest: Identifiable {
        let id = UUID()
        let moves: [Move]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                standing
                HStack(alignment: .top, spacing: 8) {
                    AdvantageBar(
                        score: session.analysis?.best?.score, orientation: session.orientation
                    )
                    board
                }
                enginePanel
                movetext
                browsing
                variations
                settings
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .navigationTitle("对局")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if session.origin == .recognised {
                        Button {
                            path.append(.confirm(PositionProposal(reopening: session)))
                        } label: {
                            Label("编辑局面", systemImage: "square.and.pencil")
                        }
                    }
                    Button {
                        path.append(.review(session))
                    } label: {
                        Label("复盘", systemImage: "chart.line.uptrend.xyaxis")
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
            // Re-attached on every appearance: the engine may have finished starting while
            // the library was on screen, and coming back from a Review means the search
            // this screen wants is not the one that just ran.
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        .onDisappear { session.suspend() }
        .onChange(of: isSoundOn) { _, isOn in Feedback.shared.isSoundOn = isOn }
        .onChange(of: engine.isReady) { _, ready in
            guard ready else { return }
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
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

    private var standing: some View {
        HStack(spacing: 8) {
            Text(viewed.chineseStanding)
                .font(.subheadline.weight(.medium))
            if session.isThinking {
                ProgressView().controlSize(.small)
                // Mirrored Time means the engine takes about as long as the player did, which
                // is usually right and sometimes far longer than anyone wants to sit through.
                // This does not pick a different move — Stockfish reports its best line when
                // stopped — it just stops waiting.
                Button("马上走") { session.moveNow() }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            Spacer()
            ScoreLabel(score: session.analysis?.best?.score, prominent: true)
        }
    }

    private var board: some View {
        BoardView(
            pieces: pieces,
            orientation: session.orientation,
            lastMove: session.lastMove,
            checks: checkSquares,
            selected: selected,
            destinations: Set(candidateMoves.map(\.to)),
            captures: Set(candidateMoves.filter(\.isCapture).map(\.to)),
            recommendation: recommendation,
            isInteractive: session.isHandTurn,
            onTap: tap
        )
    }

    @ViewBuilder private var enginePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let analysis = session.analysis {
                HStack {
                    Text("深度 \(analysis.depth)/\(analysis.selectiveDepth)")
                    Spacer()
                    Text("\(analysis.nodesPerSecond / 1000)k 结点/秒")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(Array(analysis.lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ScoreLabel(score: line.score, prominent: index == 0)
                            .frame(width: 62, alignment: .leading)
                        Text(line.san.prefix(8).joined(separator: " "))
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                    }
                }
            } else if engine.isReady, !viewed.isOver {
                Text("引擎正在看这个局面…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if case .unavailable(let reason) = engine.status {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92, alignment: .top)
        // The recommendation keeps changing as the search deepens, and that is the point
        // (docs/adr/0009) — so it must not make the layout jump while it does.
        .animation(.none, value: session.analysis?.depth)
    }

    private var movetext: some View {
        ScrollView {
            Text(movetextString)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 54)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Walking through the game. Going back here is looking, not undoing — the moves stay
    /// where they are, and playing something else from an earlier position keeps what used to
    /// follow as a Variation rather than throwing it away.
    private var browsing: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    selected = nil
                    session.step(by: -1)
                } label: {
                    Label("上一步", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(session.cursor == 0)

                Button {
                    selected = nil
                    session.step(by: 1)
                } label: {
                    Label("下一步", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(session.isAtLatest)

                Button {
                    selected = nil
                    session.undo()
                } label: {
                    Label("悔棋", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!session.isAtLatest || session.game.plies.isEmpty)
            }

            if !session.isAtLatest {
                HStack {
                    Text("在看第 \(session.cursor)/\(session.game.plies.count) 步")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("回到最新") {
                        selected = nil
                        session.jumpToLatest()
                    }
                    .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder private var variations: some View {
        let lines = session.variationsHere
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("这里还走过别的").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Button {
                        selected = nil
                        session.enterVariation(index)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(line.prefix(6).map(\.san).joined(separator: " "))
                                .font(.footnote.monospaced())
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settings: some View {
        VStack(spacing: 10) {
            // Which way up the board is, kept on screen next to who started, because they are
            // the two things about a game that a picture cannot settle and a player may want
            // to change at any point.
            ChipPair(
                title: "视角",
                options: [
                    .init(value: Orientation.whiteAtBottom, label: "白在下"),
                    .init(value: Orientation.blackAtBottom, label: "黑在下"),
                ],
                selection: session.orientation
            ) { orientation in
                withAnimation(.snappy(duration: 0.2)) { session.orientation = orientation }
            }

            // Kept on screen for the whole game, not only at the start: it is how a game is
            // restarted, and it says which side began even when that is twenty moves ago.
            ChipPair(
                title: "先走方",
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

            if !session.game.plies.isEmpty {
                Text("点「白先走」或「黑先走」会从头开始；已经走过的这局会留在对局记录里。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach([PieceColour.white, .black], id: \.self) { colour in
                HStack {
                    Text(colour.chinese).font(.subheadline)
                    Spacer()
                    Picker(colour.chinese, selection: controllerBinding(colour)) {
                        ForEach(Controller.allCases, id: \.self) { controller in
                            Text(controller.chinese).tag(controller)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .disabled(!engine.isReady)
                }
            }
        }
    }

    // ------------------------------------------------------------------ doing

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

    /// The game as it stands where the player is looking, which is the position everything on
    /// this screen is about — the board, the legal moves, and what the engine is analysing.
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

    private var movetextString: AttributedString {
        var text = AttributedString()
        var number = Int(session.game.startFEN.split(separator: " ").last.flatMap { Int($0) } ?? 1)
        var sideToMove: PieceColour =
            session.game.startFEN.split(separator: " ").dropFirst().first == "b" ? .black : .white

        for (index, ply) in session.game.plies.enumerated() {
            if sideToMove == .white {
                text += plain("\(number). ")
            } else if text.characters.isEmpty {
                text += plain("\(number)... ")
            }
            // The move that led to the position on screen, so browsing has somewhere to point.
            var san = plain(ply.san)
            if index == session.cursor - 1 {
                san.font = .footnote.monospaced().bold()
                san.foregroundColor = .accentColor
            }
            text += san
            if !ply.variations.isEmpty {
                var mark = plain(" (+\(ply.variations.count))")
                mark.foregroundColor = .secondary
                text += mark
            }
            text += plain(" ")
            if sideToMove == .black { number += 1 }
            sideToMove = sideToMove.opposite
        }
        return text.characters.isEmpty ? plain("还没走棋。") : text
    }

    private func plain(_ string: String) -> AttributedString {
        var piece = AttributedString(string)
        piece.font = .footnote.monospaced()
        return piece
    }

    private func controllerBinding(_ colour: PieceColour) -> Binding<Controller> {
        Binding(
            get: { session.controller(for: colour) },
            set: { session.setController($0, for: colour) }
        )
    }
}
