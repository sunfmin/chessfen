import ChessfenKit
import SwiftUI
import UIKit

/// What recognition proposes, on its way to the gate.
struct PositionProposal: Identifiable, Hashable {
    let id = UUID()
    var draft: PositionDraft
    /// The Shaky Squares — where the classifier was not confident.
    var shaky: Set<Square> = []
    var orientation: Orientation = .whiteAtBottom
    /// The picture it was read from, so the player can check it against the board.
    var picture: RGBImage?
    /// Carried through to the game, so a corrected position is still a recognised one.
    var origin: GameOrigin = .recognised
    var controllers: [PieceColour: Controller] = [.white: .hand, .black: .hand]

    /// Sends a game that came off a picture back to the gate, to fix a piece that was read
    /// wrong. What comes out is a new game from the corrected position: the moves already
    /// played were played in a position that turned out not to be the one on the table, so
    /// they cannot be carried over — and the old record stays in the library either way.
    init(reopening session: GameSession) {
        draft = PositionDraft(fen: session.game.startFEN) ?? PositionDraft(pieces: [:])
        shaky = session.shaky
        orientation = session.orientation
        picture = session.picture
        origin = session.origin
        controllers = [
            .white: session.controller(for: .white), .black: session.controller(for: .black),
        ]
    }

    init(
        draft: PositionDraft,
        shaky: Set<Square> = [],
        orientation: Orientation = .whiteAtBottom,
        picture: RGBImage? = nil,
        origin: GameOrigin = .recognised,
        controllers: [PieceColour: Controller] = [.white: .hand, .black: .hand]
    ) {
        self.draft = draft
        self.shaky = shaky
        self.orientation = orientation
        self.picture = picture
        self.origin = origin
        self.controllers = controllers
    }

    // Identity, not contents: the draft is edited at the gate and the navigation stack
    // must not treat an edited proposal as a different destination.
    static func == (left: PositionProposal, right: PositionProposal) -> Bool {
        left.id == right.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The Confirm Position gate: every recognised board comes through here (docs/adr/0008).
///
/// Recognition is very good and not perfect, and a wrong piece is not a wrong pixel — it is
/// a different game, with different best moves, discovered ten moves later. So this screen
/// exists to be passed through deliberately: the reading is shown with its doubts marked,
/// every square can be corrected, and the fields no picture could have shown are asked
/// rather than assumed.
struct ConfirmPositionScreen: View {
    let proposal: PositionProposal
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var draft: PositionDraft
    @State private var orientation: Orientation
    /// The piece taps place. Nil means taps do nothing, which is where this starts: the
    /// first thing a player does here is look, and a board that changes under a stray
    /// finger would undo the point of the screen.
    @State private var brush: Brush?
    @State private var isPictureShowing = false
    /// Both by hand to begin with; the engine is one tap away, here or in the game. A game
    /// coming back here to be corrected brings whatever it was already set to.
    @State private var controllers: [PieceColour: Controller]

    enum Brush: Hashable {
        case piece(Piece)
        case eraser
    }

    init(proposal: PositionProposal, path: Binding<[Step]>) {
        self.proposal = proposal
        _path = path
        _draft = State(initialValue: proposal.draft)
        _orientation = State(initialValue: proposal.orientation)
        _controllers = State(initialValue: proposal.controllers)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                board
                shakyNote
                palette
                fields
                fenRow
                players
                startButton
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("确认局面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("摆回初始局面") { draft.reset() }
                    Button("清空棋盘") { draft.clear() }
                    if proposal.picture != nil {
                        Button("看原图") { isPictureShowing = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPictureShowing) {
            if let picture = proposal.picture, let image = Image(rgb: picture) {
                NavigationStack {
                    image
                        .resizable()
                        .scaledToFit()
                        .navigationTitle("原图")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    // ------------------------------------------------------------------ parts

    private var board: some View {
        BoardView(
            pieces: draft.pieces,
            orientation: orientation,
            suspects: proposal.shaky,
            coordinates: true,
            onTap: paint
        )
    }

    @ViewBuilder private var shakyNote: some View {
        if !proposal.shaky.isEmpty {
            let names = proposal.shaky.sorted { $0.index < $1.index }.map(\.description)
            Label(
                "有 \(names.count) 个格子不太确定：\(names.joined(separator: "、"))。橙色框就是它们。",
                systemImage: "questionmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(brush == nil ? "改棋子：先选一个笔，再点格子" : "点格子放下，再点笔可换")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(palettePieces, id: \.glyph) { piece in
                        Button {
                            brush = brush == .piece(piece) ? nil : .piece(piece)
                        } label: {
                            PieceGlyphView(piece: piece)
                                .frame(width: 38, height: 38)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            brush == .piece(piece)
                                                ? Color.accentColor.opacity(0.25)
                                                : Color.secondary.opacity(0.12)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        brush = brush == .eraser ? nil : .eraser
                    } label: {
                        Image(systemName: "eraser")
                            .frame(width: 38, height: 38)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        brush == .eraser
                                            ? Color.accentColor.opacity(0.25)
                                            : Color.secondary.opacity(0.12)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            // Worded as it is on the game screen, where the same choice restarts a game.
            Picker("先走方", selection: $draft.sideToMove) {
                Text("白先走").tag(PieceColour.white)
                Text("黑先走").tag(PieceColour.black)
            }
            .pickerStyle(.segmented)

            Picker("视角", selection: $orientation) {
                Text("白在下").tag(Orientation.whiteAtBottom)
                Text("黑在下").tag(Orientation.blackAtBottom)
            }
            .pickerStyle(.segmented)

            if !draft.possibleCastling.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("易位权").font(.subheadline)
                        Spacer()
                        Button("按棋子推断") { draft.grantCastlingFromHomeSquares() }
                            .font(.footnote)
                    }
                    HStack(spacing: 8) {
                        ForEach(castlingRights, id: \.right) { entry in
                            Toggle(entry.label, isOn: binding(for: entry.right))
                                .toggleStyle(.button)
                                .font(.footnote)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !draft.possibleEnPassantSquares.isEmpty {
                HStack {
                    Text("吃过路兵").font(.subheadline)
                    Spacer()
                    Menu {
                        Button("无") { draft.enPassant = nil }
                        ForEach(draft.possibleEnPassantSquares, id: \.self) { square in
                            Button(square.description) { draft.enPassant = square }
                        }
                    } label: {
                        Text(draft.enPassant?.description ?? "无")
                    }
                }
            }
        }
    }

    private var fenRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(draft.fen)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = draft.fen
            } label: {
                Image(systemName: "doc.on.doc")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var players: some View {
        VStack(spacing: 10) {
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
                    .frame(width: 160)
                    .disabled(!engine.isReady)
                }
            }
            if !engine.isReady {
                Text("引擎还没准备好，先两边手动也行——进对局后随时能改。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            if let issue = draft.verdict.issue {
                Label(issue.chinese, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                start()
            } label: {
                Text("开始对局")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!draft.isPlayable)
        }
    }

    // ------------------------------------------------------------------ doing

    private func paint(_ square: Square) {
        switch brush {
        case .none: return
        case .eraser: draft.setPiece(nil, at: square)
        case .piece(let piece):
            // Tapping the same piece onto the square it already occupies takes it off,
            // which is what a finger expects and saves a trip to the eraser.
            draft.setPiece(draft.piece(at: square) == piece ? nil : piece, at: square)
        }
    }

    private func start() {
        guard let game = draft.game else { return }
        let session = GameSession(
            game: game,
            controllers: controllers,
            orientation: orientation,
            origin: proposal.origin,
            picture: proposal.picture,
            shaky: proposal.shaky
        )
        session.attach(engine: engine.service, library: library)
        // Not saved here. A recognised position nobody has moved in yet is not a game, and
        // people come through this gate constantly just to see what the engine thinks — the
        // first move is what makes a record worth keeping (see GameSession.save).
        // Replaces the gate rather than stacking on it: going back from a game in progress
        // belongs in the library, not in the editor of a position already being played.
        path = [.game(session)]
    }

    private var palettePieces: [Piece] {
        [PieceColour.white, .black].flatMap { colour in
            PieceKind.allCases.reversed().map { Piece(colour: colour, kind: $0) }
        }
    }

    private var castlingRights: [(right: Character, label: String)] {
        [("K", "白 O-O"), ("Q", "白 O-O-O"), ("k", "黑 O-O"), ("q", "黑 O-O-O")]
            .filter { draft.possibleCastling.contains($0.0) }
            .map { (right: $0.0, label: $0.1) }
    }

    private func binding(for right: Character) -> Binding<Bool> {
        Binding(
            get: { draft.castling.contains(right) },
            set: { isOn in
                if isOn {
                    draft.castling.insert(right)
                } else {
                    draft.castling.remove(right)
                }
            }
        )
    }

    private func controllerBinding(_ colour: PieceColour) -> Binding<Controller> {
        Binding(
            get: { controllers[colour] ?? .hand },
            set: { controllers[colour] = $0 }
        )
    }
}
